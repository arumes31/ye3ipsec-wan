# Build

To customize and create your own images.

```bash
git clone https://github.com/arumes31/ye3ipsec-wan.git
cd ye3ipsec-wan
# Make all your modifications, then :
podman build --no-cache --network=host -t ye3ipsec-wan .
podman run --cap-add NET_ADMIN,NET_RAW -dt --name my_customized_ipsec ye3ipsec-wan
# Verify
podman logs my_customized_ipsec
podman exec -it my_customized_ipsec sh -c "swanctl --version ; swanctl --stats"
```

If you edit files from Windows to Linux, you may encounter problems with the build. You need to use UNIX-style line endings, before building

```bash
find /PATH/OF/YE3IPSEC-WAN/SOURCE/ -type f -print0 | xargs -0 dos2unix --
```
