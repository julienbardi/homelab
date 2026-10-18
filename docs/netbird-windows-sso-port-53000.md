# NetBird SSO Login Fails Due to Reserved Port 53000

## Symptom

```text
netbird up

Error: daemon up failed: sso login failed:
listen tcp :53000: bind:
An attempt was made to access a socket in a way forbidden by its access permissions.
```

NetBird cannot start the local OAuth/PKCE callback listener on `localhost:53000`.

## Diagnosis

Check whether port 53000 falls within a Windows excluded port range:

```powershell
netsh int ipv4 show excludedportrange protocol=tcp
```

Example:

```text
52924 - 53023
```

Since port `53000` lies within this range, the `bind()` operation fails even though no process is listening on the port.

## Root Cause

Windows HNS/WinNAT (often used indirectly by WSL2, Docker Desktop, Hyper-V, or other virtualization features) reserves blocks of dynamic ports.

NetBird uses `http://localhost:53000/` as the default callback URL during the SSO login flow. If Windows reserves port 53000, the OAuth callback listener cannot start and authentication fails.

## Solution

Reserve port 53000 explicitly before WinNAT can claim it:

```cmd
net stop winnat

netsh int ipv4 add excludedportrange protocol=tcp startport=53000 numberofports=1 store=persistent

net start winnat
```

Then retry:

```powershell
netbird up
```

The SSO login should complete successfully.

## Verification

Confirm that the excluded range no longer contains a larger dynamic block covering port 53000:

```powershell
netsh int ipv4 show excludedportrange protocol=tcp
```

Verify that NetBird can authenticate:

```powershell
netbird up
netbird status -d
```

## Reference Log Entries

```text
pkce flow: waiting for authorization callback on http://localhost:53000/

waiting for browser login failed:
listen tcp :53000: bind:
An attempt was made to access a socket in a way forbidden by its access permissions.
```

## Notes

This issue is not caused by WireGuard, routing, or NetBird Cloud connectivity.

The failure occurs before authentication completes because Windows prevents NetBird from binding its local OAuth callback listener.