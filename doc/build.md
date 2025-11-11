# Build

To customize and create your own images.

```bash
git clone https://github.com/palw3ey/ye3ipsec.git
cd ye3ipsec
# Make all your modifications, then :
podman build --no-cache --network=host -t ye3ipsec .
podman run --cap-add NET_ADMIN,NET_RAW -dt --name my_customized_ipsec ye3ipsec
# Verify
podman logs my_customized_ipsec
podman exec -it my_customized_ipsec sh -c "swanctl --version ; swanctl --stats"
```

By default the strongswan downloaded is from the tarball release, if you prefer the version of the github master I have included a Dockerfile adapted for a build from the master. Usefull if you really need the latest commit and bug fixes :

```bash
podman build -f Dockerfile_master --no-cache --network=host -t ye3ipsec .
```

If you edit files from Windows to Linux, you may encounter problems with the build. You need to use UNIX-style line endings, before building

```bash
find /PATH/OF/YE3IPSEC/SOURCE/ -type f -print0 | xargs -0 dos2unix --
```
