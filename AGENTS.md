# Repository working rules

- Before editing any existing source, documentation or test file, create and verify a new timestamped backup of the current repository files outside this repository. Exclude .git metadata. Keep a SHA-256 file inventory and never overwrite an older backup.
- Preserve the diagnostics -> review -> explicit apply flow and default-No download consent. Do not execute real repairs/installer changes merely to test code.
- The backup requirement concerns repository files only. Do not add or require a backup/snapshot of the user-side DSS installation. Preserve installer validation and the existing PATH/hosts repair safeguards.
- Do not commit, push or publish changes without the user's explicit approval.
