#!/bin/sh
set -e  # Work even if somebody does "sh thisscript.sh".

# If not --_skip-to-install:
    # Bootstrap
    # TODO: Inline the bootstrap scripts by putting each one into its own function (so they don't leak scope).

PYTHON=python
SUDO=sudo

if [ "$1" != "--_skip-to-install" ]; then
    # Now we drop into python so we don't have to install even more
    # dependencies (curl, etc.), for better flow control, and for the option of
    # future Windows compatibility.
    #
    # The following Python script prints a path to a new copy
    # of letsencrypt-auto or returns non-zero.
    # There is no $ interpolation due to quotes on heredoc delimiters.
    set +e
    DOWNLOAD_OUT=`$PYTHON - <<-"UNLIKELY_EOF"

from json import loads
from os.path import join
from subprocess import check_call, CalledProcessError
from sys import exit
from tempfile import mkdtemp
from urllib2 import build_opener, HTTPHandler, HTTPSHandler, HTTPError


PUBLIC_KEY = """-----BEGIN PUBLIC KEY-----
MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAnwHkSuCSy3gIHawaCiIe
4ilJ5kfEmSoiu50uiimBhTESq1JG2gVqXVXFxxVgobGhahSF+/iRVp3imrTtGp1B
2heoHbELnPTTZ8E36WHKf4gkLEo0y0XgOP3oBJ9IM5q8J68x0U3Q3c+kTxd/sgww
s5NVwpjw4aAZhgDPe5u+rvthUYOD1whYUANgYvooCpV4httNv5wuDjo7SG2V797T
QTE8aG3AOhWzdsLm6E6Tl2o/dR6XKJi/RMiXIk53SzArimtAJXe/1GyADe1AgIGE
33Ja3hU3uu9lvnnkowy1VI0qvAav/mu/APahcWVYkBAvSVAhH3zGNAGZUnP2zfcP
rH7OPw/WrxLVGlX4trLnvQr1wzX7aiM2jdikcMiaExrP0JfQXPu00y3c+hjOC5S0
+E5P+e+8pqz5iC5mmvEqy2aQJ6pV7dSpYX3mcDs8pCYaVXXtCPXS1noWirCcqCMK
EHGGdJCTXXLHaWUaGQ9Gx1An1gU7Ljkkji2Al65ZwYhkFowsLfuniYKuAywRrCNu
q958HnzFpZiQZAqZYtOHaiQiaHPs/36ZN0HuOEy0zM9FEHbp4V/DEn4pNCfAmRY5
3v+3nIBhgiLdlM7cV9559aDNeutF25n1Uz2kvuSVSS94qTEmlteCPZGBQb9Rr2wn
I2OU8tPRzqKdQ6AwS9wvqscCAwEAAQ==
-----END PUBLIC KEY-----
"""  # TODO: Replace with real one.


class HumanException(Exception):
    """A novice-readable exception that also carries the original exception for
    debugging"""


class HttpsGetter(object):
    def __init__(self):
        """Build an HTTPS opener."""
        # Based on pip 1.4.1's URLOpener
        # This verifies certs on only Python >=2.7.9.
        self._opener = build_opener(HTTPSHandler())
        # Strip out HTTPHandler to prevent MITM spoof:
        for handler in self._opener.handlers:
            if isinstance(handler, HTTPHandler):
                self._opener.handlers.remove(handler)

    def get(self, url):
        """Return the document contents pointed to by an HTTPS URL.

        If something goes wrong (404, timeout, etc.), raise HumanException.

        """
        try:
            return self._opener.open(url).read()
        except (HTTPError, IOError) as exc:
            raise HumanException("Couldn't download %s." % url, exc)


class TempDir(object):
    def __init__(self):
        self.path = mkdtemp()

    def write(self, contents, filename):
        """Write something to a named file in me."""
        with open(join(self.path, filename), 'w') as file:
            file.write(contents)


def latest_stable_tag(get):
    """Return the git tag pointing to the latest stable release of LE.

    If anything goes wrong, raise HumanException.

    """
    try:
        json = get('https://pypi.python.org/pypi/letsencrypt/json')
    except (HTTPError, IOError) as exc:
        raise HumanException("Couldn't query PyPI for the latest version of "
                             "Let's Encrypt.", exc)
    metadata = loads(json)
    # TODO: Make sure this really returns the latest stable version, not just the
    # newest version. https://wiki.python.org/moin/PyPIJSON says it should.
    return 'v' + metadata['info']['version']


def verified_new_le_auto(get, tag, temp):
    """Return the path to a verified, up-to-date letsencrypt-auto script.

    If the download's signature does not verify or something else goes wrong,
    raise HumanException.

    """
    root = ('https://raw.githubusercontent.com/letsencrypt/letsencrypt/%s/' %
            tag)
    temp.write(get(root + 'letsencrypt-auto'), 'letsencrypt-auto')
    temp.write(get(root + 'letsencrypt-auto.sig'), 'letsencrypt-auto.sig')
    temp.write(PUBLIC_KEY, 'public_key.pem')
    le_auto_path = join(temp.path, 'letsencrypt-auto')
    try:
        check_call('openssl', 'dgst', '-sha256', '-verify',
                   join(temp.path, 'public_key.pem'),
                   '-signature',
                   join(temp.path, 'letsencrypt-auto.sig'),
                   le_auth_path)
    except CalledProcessError as exc:
        raise HumanException("Couldn't verify signature of downloaded "
                             "letsencrypt-auto.", exc)
    else:  # belt & suspenders
        return le_auto_path


def main():
    get = HttpsGetter().get
    temp = TempDir()
    try:
        stable_tag = latest_stable_tag(get)
        print verified_new_le_auto(get, stable_tag, temp)
    except HumanException as exc:
        print exc.args[0], exc.args[1]
        return 1
    else:
        return 0


exit(main())
"UNLIKELY_EOF"`
    DOWNLOAD_STATUS=$?
    set -e
    if [ "$DOWNLOAD_STATUS" = 0 ]; then
        NEW_LE_AUTO="$DOWNLOAD_OUT"
        $SUDO cp "$NEW_LE_AUTO" $0
    else
        # Report error:
        echo $DOWNLOAD_OUT
    fi
else  # --_skip-to-install was passed.
    echo skipping!
fi

echo $TMP_DIR
