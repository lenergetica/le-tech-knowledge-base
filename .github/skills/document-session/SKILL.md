---
name: "document-session"
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
     (currently configured in `zensical.toml`). Put the page beside related
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
   - The KB uses Zensical with the `modern` theme and `zensical.toml`.
     The first production release is still pending. Dependencies are pinned in
     `requirements.txt`; install them in a virtual environment with Python 3.14.
     The GitHub Actions workflow builds with `zensical build --clean` and
     publishes the `site/` artifact to GitHub Pages. Deployment to Edison is
     pending; do not describe it as completed.
   - Use Zensical's native Mermaid integration. Do not add a second CDN script
     or custom Mermaid initializer. Keep document metadata and review warnings
     working when changing templates or JavaScript.
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
   author: "<nom de l'usuari que crea el document>"
   reviewed_by: "<nom de l'usuari que fa aquesta actualització o revisió>"
   owner: "Equip de Tecnologia de L'Energètica"
   status: "draft"
   version: "1.0"
   creation_date: "YYYY-MM-DD"
   review_date: "YYYY-MM-DD"
   review_after_months: 60
   tags:
     - "<tema>"
   references: []
   ---
   ```

   - Keep `author` and `reviewed_by` together, and group `creation_date`,
     `review_date`, and `review_after_months` in that order.
     Dates use quoted `YYYY-MM-DD` values, without a time component. Use double
     quotes for all text values, including names, statuses, versions, tags, and
     references; keep integers such as `review_after_months` unquoted.
   - For a new document, use today's date for `creation_date` and
     `review_date`. For an existing document, preserve its creation date;
     migrate the old `created` value to `creation_date`. If no date is recorded,
     the first verifiable Git addition can serve as a reference. Omit the field
     if there is insufficient evidence rather than inventing a date.
   - For a new document, set both `author` and `reviewed_by` to the name of the
     user creating it. Prefer a name explicitly supplied by the user; otherwise
     use `git config user.name` in the repository. Preserve `author` on later
     edits, and update `review_date` and `reviewed_by` for the current user.
     For AI-assisted edits, attribute the change to that user, not the assistant.
     If the user or original author cannot be determined, ask rather than
     inventing a name. Do not substitute the last commit author or treat this
     attribution as evidence of functional approval.
   - Use `review_date` for the latest document update or review, including
     formatting and metadata edits; do not add a separate modification date.
     Keep this field name compatible with the site's existing review warnings.
     This date does not imply functional approval: new documents start as
     `draft`. The repository's pre-push hook asks the user whether outgoing
     drafts should become `active`; never approve that change on the user's
     behalf. Accepting stops the push so the user can review and commit the
     change before pushing again.
   - Use `review_after_months` for the months after `review_date` when the
     document needs review because it may be outdated. The default is 60 months;
     preserve an existing explicit interval unless a change is requested.
     New front matter uses this name instead of `review_period_months`.
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
