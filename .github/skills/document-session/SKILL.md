---
name: document-session
description: "Use when asked to document work from a chat session, write up what was done, add a knowledge-base article or runbook, or turn decisions and troubleshooting into team documentation. Follows this repository's Markdown, metadata, folder, and Zensical navigation conventions."
---

# Document a chat session for the Tech Knowledge Base

Turn useful work from the current or a previous chat session into accurate,
maintainable documentation in this repository. Produce an actionable knowledge
base page, not a transcript or a speculative summary.

## Workflow

1. **Gather evidence**
   - Review the relevant conversation, including earlier decisions and final
     outcomes. Inspect related repository files and current documentation
     conventions before drafting.
   - Separate verified facts, decisions, commands actually run, and unresolved
     points. Do not present proposals or failed attempts as completed work.
   - If critical facts are missing or contradictory, ask the user before
     documenting them. Do not invent hostnames, versions, owners, outcomes, or
     operational commands.

2. **Choose the document location**
   - Follow the existing `docs/` taxonomy and the Zensical site navigation
     (currently configured in `mkdocs.yml`). Put the page beside related
     material; create a folder only when it represents a useful category.
   - For a new page, add it to the appropriate `nav` section in the site
     configuration. Avoid duplicate pages; update the existing page if it
     already covers the topic.
   - Store reusable scripts and other supporting files in an appropriate
     `docs/scripts/` subfolder and link to them with relative paths. Store
     images in `docs/images/` unless the surrounding section has an established
     local convention.

3. **Create useful documentation**
   - Write in Catalan by default, matching the repository's existing material
     unless the user requests another language.
   - The KB is based on Zensical and is published at
     [https://edison.gcc.intranet.gencat.cat/kb](https://edison.gcc.intranet.gencat.cat/kb).
     Zensical can use the existing `mkdocs.yml` configuration. The deployment
     workflow may still contain MkDocs commands; do not change it as part of a
     documentation task unless the user asks.
   - Use Zensical commands for local previews and builds, and verify any
     tooling-specific instructions against
     [Zensical's documentation](https://zensical.org/docs/get-started/).
   - Start with the purpose and scope. Use clear headings and concise,
     operational instructions.
   - Include prerequisites, steps, expected results, verification, risks or
     rollback guidance where applicable. Explain important decisions and
     limitations so another team member can use the document without the chat.
   - Include commands only when verified from the conversation or repository.
     Mark placeholders clearly; never include passwords, tokens, private keys,
     or other secrets.
   - Link to related pages and scripts rather than copying their content.

4. **Add YAML front matter**
   - Follow [the KB metadata and writing guide](../../../docs/index.md), which
     is the source of truth for fields and Markdown conventions.
   - Add front matter to the document using this starter. Replace every
     placeholder and keep only relevant optional fields.

   ```yaml
   ---
   title: "<títol clar i descriptiu>"
   author: "<persona autora o Equip de Tecnologia>"
   owner: L'Energetica Tech
   status: draft
   version: 1.0
   review_date: "YYYY-MM-DD"
   review_period_months: 6
   tags:
     - "<tema>"
   references: []
   created: "YYYY-MM-DD"
   ---
   ```

   - Use today's date for `created` and `review_date` when creating a new
     document. If an individual author is not known, use `Equip de Tecnologia`
     rather than guessing a person's name. Keep the initial status as `draft`
     unless the user explicitly confirms review or approval.
   - Choose a small set of useful tags. Add `references` only for real sources;
     remove the field if there are none.

5. **Validate and report**
   - Check the front matter, heading hierarchy, spelling, internal relative
     links, image paths, code fences, and any site-navigation change.
   - Run the repository's available documentation build or link check if
     practical. Do not claim validation that was not run.
   - Summarize the created or updated files, the main content captured, and any
     remaining uncertainty or review required.

## Quality bar

- Preserve the difference between what happened, what was decided, and what is
  still proposed.
- Keep operational warnings and destructive-action confirmations explicit.
- Prefer reproducible steps and expected outputs over narrative detail.
- Keep the page self-contained enough to use later, but avoid duplicating
  information already maintained elsewhere in the KB.
