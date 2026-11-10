# A locked login keyring is not a lost password

`login.keyring` is the GNOME login keyring of ctodie on ceres. GitButler, `rev`
and other tools keep their tokens in it.

- **At boot,** `gnome-keyring-daemon.service` starts it unlocked. Its ExecStart,
  `~/.local/bin/keyring-daemon-start`, reads the password from
  `op://cloud/ceres-gnome-login-keyring/password` using the workstation service account.
- **If it is locked,** run `keyring-unlock`. If the service account can't reach
  1Password, run `keyring-unlock --windows` and approve in the 1Password app.
  `keyring-unlock --check` prints the state.
- **Never move, delete or recreate `login.keyring`.** A locked keyring does not
  mean the password is lost. Neither does a write that hangs, or an
  "authorization timeout" from op.exe. Resets on 2026-10-02, 2026-10-17 and
  2026-11-10 each lost every secret stored here. If the unlock really fails,
  stop and ask Christian.

Older keyrings kept here:

| File | Password |
|---|---|
| `login.keyring.lost-password-20261002` | `op://cloud/wsl-gnome-keyring-login/password` |
| `login.keyring.lost-password-20261017` | unknown |
| `login.keyring.lost-password-20261110` | unknown, possibly the workstation-keys password |
| `login.keyring.empty-20261110` | unknown (the empty keyring from the 06:11Z reset) |
