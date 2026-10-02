# Code signing (free, SignPath Foundation)

> **Status (Oct 2026): not signed.** SignPath Foundation turned down the application (new projects with few users
> often are). Nothing else is free, so the installer stays unsigned and the install page explains "More info > Run
> anyway". Everything below stays ready: re-apply later, and if approved, add the two secrets - no code changes needed.

Goal: the install page's download is a signed `Install-Messiah.exe`, so Windows shows no "Windows protected your PC"
warning. Everything on the kit's side is ready; only the owner's own steps below are left (they need your accounts).

## Already done in the repo

- `LICENSE` (MIT) - SignPath Foundation only signs open-source projects.
- `tools/installer/Installer.cs` + `build.ps1` - the installer exe, built from source with the C# compiler that comes
  with Windows. It only starts the published one-line installer (`install.ps1`).
- `.github/workflows/sign.yml` - for every release: builds the exe on GitHub, sends it to SignPath, checks the
  signature and attaches `Install-Messiah.exe` to the release. Without the secrets below it only builds (as a check)
  and attaches nothing.
- `docs/code-signing.html` - the code signing policy page SignPath Foundation asks for
  (https://kevincxv.github.io/pc-setup-kit/code-signing.html), linked from the install page.

## Your steps (about 15 minutes, then waiting for approval)

1. Turn on two-factor authentication on GitHub if it isn't (SignPath requires it for everyone on the project).
2. Apply at https://signpath.org/apply with:
   - Project: pc-setup-kit - https://github.com/Kevincxv/pc-setup-kit
   - What's signed: `Install-Messiah.exe`, built by GitHub Actions from `tools/installer/Installer.cs`
   - License: MIT. Code signing policy: https://kevincxv.github.io/pc-setup-kit/code-signing.html
3. Once approved, in the SignPath web app:
   - Install the SignPath GitHub app on the repository (it checks that the file really came from GitHub Actions).
   - Create a project with the slug `pc-setup-kit`, linked to the repository.
   - Artifact configuration, slug `installer`:
     ```xml
     <artifact-configuration xmlns="http://signpath.io/artifact-configuration/v1">
       <zip-file>
         <pe-file path="Install-Messiah.exe">
           <authenticode-sign/>
         </pe-file>
       </zip-file>
     </artifact-configuration>
     ```
   - Signing policy, slug `release-signing` (the Foundation's certificate), with you as approver.
   - Create an API token for a CI user that may submit to that policy.
4. In GitHub: repository > Settings > Secrets and variables > Actions > New repository secret:
   - `SIGNPATH_API_TOKEN` - the token from step 3
   - `SIGNPATH_ORGANIZATION_ID` - shown in SignPath under your organization's settings
5. Tell Claude it's set up. The next release is signed; once a signed `Install-Messiah.exe` is on it, the install
   page's button is switched to it (the `.cmd` stays as a fallback for old links).

Costs nothing: SignPath Foundation's certificate and signing are free for open-source projects.
