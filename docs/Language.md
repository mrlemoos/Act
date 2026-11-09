# Domain language

Define business concepts, not frameworks, libraries or implementation types. One authoritative definition per term. Root glossary links domain-owned glossaries when needed.

| Term | Meaning | Example | Distinction |
|---|---|---|---|
| Screenplay | Authoritative UTF-8 Fountain source edited by the writer | FirstLight.fountain | AI planning never rewrites it |
| Scene anchor | Stored scene identity and source fingerprint used to associate planned shots | Numbered scene 1 plus its text hash | A changed or missing scene requires review |
| Shot list | Separate editable planning document linked to screenplay scenes | FirstLight.shots.json | Not embedded into Fountain source |

Record ambiguity as unresolved. Agree meaning before updating contracts or acceptance checks. Use these terms consistently in code, specs, tickets and ADRs.
