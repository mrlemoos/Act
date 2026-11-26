import { join } from 'node:path';
const root = join(import.meta.dir, '../..');
const resources = join(root, 'Sources/ActCore/Resources');
const result = await Bun.build({ entrypoints: [join(root, 'CLI/src/blocking/editor.ts')], target: 'browser', minify: true });
if (!result.success) throw new Error(result.logs.join('\n'));
await Bun.write(join(resources, 'BlockingPlans.js'), result.outputs[0]!);
await Bun.write(join(resources, 'BlockingPlans.html'), (await Bun.file(join(import.meta.dir, 'index.html')).text()).replace('src="editor.js"', 'src="BlockingPlans.js"'));
