# Publishing adadiamonds to RubyGems

The gem is named `adadiamonds` (the brand name, matching the domain) so that
package-registry lookups by domain find it. Source lives here in
`packages/ada-ruby` and is mirrored to the public repository
`adadiamonds/ada-ruby` (the `source_code_uri` in the gemspec), the same
snapshot approach as `adadiamonds/ada-go`.

## One-time setup (Cesar)

1. Create a RubyGems account for `it@adadiamonds.com` at
   <https://rubygems.org/sign_up> and enable MFA (the gemspec sets
   `rubygems_mfa_required`, so pushes need an OTP).
2. Create an API key at <https://rubygems.org/profile/api_keys> with the
   "Push rubygems" scope. Store it in 1Password (Software Development vault)
   and put it in `~/.gem/credentials` (mode 600):

   ```yaml
   ---
   :rubygems_api_key: rubygems_xxx
   ```

3. Create the PUBLIC repository `adadiamonds/ada-ruby` on GitHub (empty; the
   first sync fills it). Description: "Official Ruby client for the Ada
   Diamonds API". Website: https://www.adadiamonds.com/developers.

## Release

Run from the monorepo root, on `main`, after the change has merged:

```bash
# 1. Bump AdaDiamonds::VERSION in packages/ada-ruby/lib/adadiamonds/version.rb
#    (the User-Agent follows it) and add a CHANGELOG entry.
# 2. Test and build.
(cd packages/ada-ruby && ruby -Ilib -Itest test/client_test.rb && gem build adadiamonds.gemspec)
# 3. Push the snapshot to the public repository and tag it.
ADA_RUBY_TAG=v0.1.0 bun run sync:ada-ruby
# 4. Publish (prompts for the MFA code).
(cd packages/ada-ruby && gem push adadiamonds-0.1.0.gem)
```

Verify:

```bash
curl -s https://rubygems.org/api/v1/gems/adadiamonds.json | head -c 400
gem install adadiamonds && ruby -e 'require "adadiamonds"; p AdaDiamonds::Client.new.diamonds(limit: 1).total'
```

The gem page shows the README, the license, and the homepage/source links;
those point back to https://www.adadiamonds.com/developers, which is how
discovery scanners confirm the gem is the official SDK.

## After the first release

- `apps/website/app/developers/sections/RubySdk.tsx`, `lib/agent/llms-sections.ts`,
  `lib/agent/agents-md.ts`, `app/api/llms-txt/route.ts`, and `lib/agent/agent-mode.ts`
  already list the gem; re-run `bun run sync:agent-tools` so the public skill
  mentions it too.
