# lxd-wordpress

Bash script to generate an LXD WordPress site, configured with a Let's Encrypt certificate and an Exim installation
for delivering WordPress notification emails.

## Getting Started

You may want to first copy 'build.sh' to something like 'build-my-site.sh', since there are some environment variables at the top of the script that should be edited according to your installation. In particular, HOST and DB_PASS will need to be set to something specific to your installation.

### Prerequisites

To run this script, you will need a working 'lxc' command on your host. See [here](https://linuxcontainers.org/lxd/getting-started-cli/) for details on installing LXD.

I used [snapd](https://docs.snapcraft.io/installing-snapd/6735) to install on Debian 9. Snap is simply a package manager by Canonical, and can be installed directly on Debian 9 onwards with 'sudo apt-get install snapd'.

### Installing

With the script edited appropriately, it should be enough to just run ./build.sh (or whatever you copied it as before editing.

When the script has finished, if all went well, you can connect to the container with 'lxc exec wp-container bash'. This will put you in a root prompt inside the container.

From here, things should look like an ordinary VPS, with Apache and Exim running. You should be able to connect to your site and follow on with the standard WordPress configuration wizard.

There are [a few notes here](https://www.susa.net/wordpress/2018/12/lxd-now-runs-my-wordpress/) from when I originally moved to LXD for WordPress.

## Contributing

This code is simply a generalised version of something I used for my own site. There's plenty of room for improvement, so pull-requests are welcome.

## Forks

https://github.com/t0mmysm1th/lxd-wordpress Tommy Smith has enhanced this script with more choice in the PHP version via the 3rd party SURY Repository, as well as self-signed SSL/TLS certificates, and some other niceties. These changes are particularly suited for deploying development or otherwise internal servers.

## License

This project is licensed under the GNU GPLv2.

## Acknowledgments

* Thanks in particular to [Neilpang](https://github.com/Neilpang/acme.sh) for his awesome acme.sh script for generating Let's Encrypt certificates. Being dependent on nothing but bash helped significantly reduce the size of the container, which was one of my goals.
