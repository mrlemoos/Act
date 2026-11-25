import { createHash } from 'node:crypto';
import { mkdtemp, mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

export function identity(sha: string, run: string) {
  if (!/^[a-f0-9]{40}$/.test(sha) || !/^[1-9][0-9]*$/.test(run)) {
    throw new Error('Expected a full commit SHA and positive Actions run ID');
  }
  const tag = `build-${run}-${sha.slice(0, 12)}`;
  return { sha, run, tag, asset: `Act-${tag}-macOS-arm64.zip` };
}

type Identity = ReturnType<typeof identity>;
export type Run = (args: string[]) => Promise<string>;
const run: Run = async (args) => {
  const process = Bun.spawn(args, { stdout: 'pipe', stderr: 'pipe' });
  const [stdout, stderr, code] = await Promise.all([
    new Response(process.stdout).text(), new Response(process.stderr).text(), process.exited,
  ]);
  if (code !== 0) throw new Error(`${args[0]} failed (${code}): ${stderr.trim()}`);
  return stdout.trim();
};
const output = '.build/download';
const digest = (bytes: Uint8Array) => createHash('sha256').update(bytes).digest('hex');

async function verifyApp(app: string, exec: Run) {
  for (const path of ['Contents/MacOS/Act', 'Contents/Helpers/act']) {
    if ((await exec(['lipo', '-archs', `${app}/${path}`])) !== 'arm64') {
      throw new Error(`Unexpected executable architecture: ${path}`);
    }
    await exec(['codesign', '--verify', '--strict', `${app}/${path}`]);
    const signature = await exec(['sh', '-c', 'codesign -dv "$1" 2>&1', 'signature', `${app}/${path}`]);
    if (!signature.includes('Signature=adhoc')) throw new Error('Expected ad-hoc signature');
  }
  await exec(['codesign', '--verify', '--deep', '--strict', app]);
  for (const path of ['Contents/Info.plist', 'Contents/Resources/Act.icns', 'Contents/Resources/Act_ActCore.bundle']) {
    await exec(['test', '-e', `${app}/${path}`]);
  }
  for (const locale of (await readdir('Resources')).filter(name => name.endsWith('.lproj'))) {
    await exec(['diff', '-rq', `Resources/${locale}`, `${app}/Contents/Resources/${locale}`]);
  }
  const schema = JSON.parse(await exec(['env', 'PATH=/usr/bin:/bin', `${app}/Contents/Helpers/act`, 'schema']));
  if (!schema || typeof schema !== 'object') throw new Error('Invalid bundled CLI schema');
}

async function packageApp(id: Identity) {
  if (await run(['git', 'rev-parse', 'HEAD']) !== id.sha) throw new Error('Checkout does not match release commit');
  // Stage only build-script outputs, never the surrounding workspace or local models.
  const staging = await mkdtemp(join(tmpdir(), 'act-download-'));
  try {
    const app = join(staging, 'Act.app');
    await run(['ditto', '.build/Act.app', app]);
    await run(['/usr/libexec/PlistBuddy', '-c', `Set :CFBundleVersion ${id.run}`, `${app}/Contents/Info.plist`]);
    await run(['codesign', '--force', '--sign', '-', `${app}/Contents/Helpers/act`]);
    await run(['codesign', '--force', '--sign', '-', app]);
    await verifyApp(app, run);
    await mkdir(output, { recursive: true });
    const archive = `${output}/${id.asset}`;
    await run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, archive]);
    const entries = (await run(['unzip', '-Z1', archive])).split('\n');
    if (entries.some(path => path.startsWith('/') || path.split('/').includes('..') ||
      !(path.startsWith('Act.app/') || path.startsWith('__MACOSX/')))) {
      throw new Error('Unexpected archive entry');
    }
    const extracted = join(staging, 'extracted');
    await run(['ditto', '-x', '-k', archive, extracted]);
    await verifyApp(`${extracted}/Act.app`, run);
    const minimum = await run(['/usr/libexec/PlistBuddy', '-c', 'Print :LSMinimumSystemVersion', `${app}/Contents/Info.plist`]);
    const manifest = { ...id, sha256: digest(await readFile(archive)) };
    await writeFile(`${output}/release.json`, `${JSON.stringify(manifest, null, 2)}\n`);
    await writeFile(`${output}/SHA256SUMS`, `${manifest.sha256}  ${id.asset}\n`);
    await writeFile(`${output}/notes.md`, `Source commit: ${id.sha}\n\nRequires macOS ${minimum} or later on Apple Silicon (arm64).\n\nDownload ${id.asset}, extract Act.app and copy it to Applications.\n\nThis build is ad-hoc signed. It is not Developer ID signed or notarised. macOS Gatekeeper may block opening it. If you trust this download, review the warning and use System Settings > Privacy & Security > Open Anyway where macOS offers it. Do not disable Gatekeeper.\n\nThe app and bundled CLI need neither Swift, Bun nor Node. Optional local inference requires a separately installed runtime and model. See the repository README for setup.\n\nSHA-256 checksums are attached.\n`);
  } finally {
    await rm(staging, { recursive: true, force: true });
  }
}

export async function publish(id: Identity, repo: string, exec: Run = run) {
  if (!/^[\w.-]+\/[\w.-]+$/.test(repo)) throw new Error('Invalid repository');
  const manifest = JSON.parse(await readFile(`${output}/release.json`, 'utf8'));
  if (manifest.sha !== id.sha || manifest.run !== id.run || manifest.tag !== id.tag || manifest.asset !== id.asset ||
      manifest.sha256 !== digest(await readFile(`${output}/${id.asset}`))) {
    throw new Error('Release artifact identity or checksum mismatch');
  }
  let existing: { draft: boolean; target_commitish: string } | undefined;
  try {
    existing = JSON.parse(await exec(['gh', 'api', `repos/${repo}/releases/tags/${id.tag}`]));
  } catch (error) {
    if (!String(error).includes('HTTP 404')) throw error;
  }
  if (existing) {
    if (existing.target_commitish !== id.sha) throw new Error('Existing release targets another commit');
    if (!existing.draft) {
      console.log('Release already published; preserving existing downloads.');
      return;
    }
  } else {
    await exec(['gh', 'release', 'create', id.tag, '--repo', repo, '--target', id.sha,
      '--title', `Act ${id.tag}`, '--notes-file', `${output}/notes.md`, '--draft']);
  }
  // Only an unpublished draft can have interrupted uploads replaced on retry.
  await exec(['gh', 'release', 'upload', id.tag, `${output}/${id.asset}`, `${output}/SHA256SUMS`, '--repo', repo, '--clobber']);
  await exec(['gh', 'release', 'edit', id.tag, '--repo', repo, '--notes-file', `${output}/notes.md`, '--draft=false', '--latest=false']);
}

if (import.meta.main) {
  const id = identity(process.env.GITHUB_SHA ?? '', process.env.GITHUB_RUN_ID ?? '');
  if (process.argv[2] === 'package') await packageApp(id);
  else if (process.argv[2] === 'publish') await publish(id, process.env.GITHUB_REPOSITORY ?? '');
  else throw new Error('Usage: bun scripts/release.ts package|publish');
}
