---
date: 2026-08-08
type: reference
tags: [template, integrations, reference]
id: 38b99f19-b2bb-5b05-a899-595ce73b5ade
---

# SERVICE NAME

<!-- One note per external service or tool an agent may need (git host,
     registrar, deploy target, mail, CI). Structure is public; the filled-in
     note lives in local/integrations/ (gitignored, never shipped). -->

## Instance

<!-- Where it lives: URL / host / region. Names only. -->

## Authentication

<!-- THE RULE: reference credentials by NAME, never by value.
     Good:  "token via `get_example_token` from ~/bin/example-helper.sh"
     Good:  "set $EXAMPLE_API_KEY (in keychain item 'example-api')"
     Bad:   any literal token, password, or key in this file.
     Agents must check this section BEFORE asking the user for credentials. -->

## Helper scripts / functions

<!-- Paths to helpers and how to call them (source vs execute matters). -->

## Common commands

<!-- The 3-5 commands you actually run against this service. -->

## Accounts & resources

<!-- Which accounts/orgs/repos/buckets exist here and what they are for. -->

## Related

- [[device notes]] this service runs on, other integrations it depends on
