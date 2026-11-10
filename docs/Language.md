# Domain language

Define business concepts, not frameworks, libraries or implementation types. One authoritative definition per term. Root glossary links domain-owned glossaries when needed.

| Term | Meaning | Example | Distinction |
|---|---|---|---|
| Screenplay | Authoritative UTF-8 Fountain source edited by the writer | FirstLight.fountain | AI planning never rewrites it |
| Scene anchor | Stored scene identity and source fingerprint used to associate planned shots | Numbered scene 1 plus its text hash | A changed or missing scene requires review |
| Shot list | Separate editable planning document linked to screenplay scenes | FirstLight.shots.json | Not embedded into Fountain source |
| Character mark | Explicitly selected name occurrence inside an action paragraph, linked to a character and colour | ORLEANS highlighted in his introduction | Does not automatically mark other occurrences or change Fountain |
| Action paragraph | Contiguous Fountain action lines containing a marked name, bounded by blank lines or another element type | A physical introduction split across two lines | Dialogue and adjacent paragraphs are excluded |
| Character reference sheet | Generated visual reference with front, profile, back and expressions | ORLEANS turnaround and expressions | An image asset, distinct from a written profile or inference model |
| Physical evidence | Exact phrase supporting a locally extracted physical detail | calloused fingers | Status, props and unspecified appearance are not physical facts |

Record ambiguity as unresolved. Agree meaning before updating contracts or acceptance checks. Use these terms consistently in code, specs, tickets and ADRs.
