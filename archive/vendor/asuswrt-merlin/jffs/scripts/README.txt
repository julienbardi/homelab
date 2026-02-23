# Asus RT-AX86U Merlin

## VPN>VPN Client>Wireguard

### Cloudeflare wgcf

DNS was `1.1.1.1,1.0.0.1,2606:4700:4700::1111,2606:4700:4700::1001`
I changed to
`10.89.12.4,1.1.1.1,1.0.0.1`
as the string is else too long for the UI to use my local DNS resolver where `10.89.12.4` is the LAN url of the machine with a full local resolver


### /jffs/scripts

# .ddns_confidential

Create a file with follwing content

```
# Instructions
# On https://manager.infomaniak.com/, go to section Dynamic DNS to set the Identifiant = DDNSUSERNAME and Mot de passe = DDNSUSERNAME used only for the DDNS update
#
# Save this in /jffs/scripts/ as .ddns_confidential
# Use chmod u+rwx go-rwx /jffs/scripts/.ddns_confidential
#
# zone information
DNS_TOPDOMAIN_NAME='example.com'
DDNSUSERNAME='DDNSUSERNAME'
DDNSPASSWORD='DDNSPASSWORD'

# Set the DEBUG variable to 1 to enable debug output. Default 0
DEBUG=0
```

### .Cloudeflare
Used to work but not longer used since introduction of token