{ lib, stdenv, fetchurl, pkg-config, perl
, brotliSupport ? false, brotli ? null
, c-aresSupport ? false, c-ares ? null
, gnutlsSupport ? false, gnutls ? null
, gsaslSupport ? false, gsasl ? null
, gssSupport ? with stdenv.hostPlatform; (
    !isWindows &&
    # disable gss becuase of: undefined reference to `k5_bcmp'
    # a very sad story re static: https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=439039
    !isStatic &&
    # the "mig" tool does not configure its compiler correctly. This could be
    # fixed in mig, but losing gss support on cross compilation to darwin is
    # not worth the effort.
    !(isDarwin && (stdenv.buildPlatform != stdenv.hostPlatform))
  ), libkrb5 ? null
, http2Support ? true, nghttp2 ? null
, http3Support ? false, nghttp3, ngtcp2 ? null
, idnSupport ? false, libidn2 ? null
, ldapSupport ? false, openldap ? null
, opensslSupport ? zlibSupport, openssl ? null
, pslSupport ? false, libpsl ? null
, rtmpSupport ? false, rtmpdump ? null
, scpSupport ? zlibSupport && !stdenv.isSunOS && !stdenv.isCygwin, libssh2 ? null
, wolfsslSupport ? false, wolfssl ? null
, zlibSupport ? true, zlib ? null
, zstdSupport ? false, zstd ? null

# for passthru.tests
, coeurl
, curlpp
, haskellPackages
, ocamlPackages
, phpExtensions
, python3
}:

# Note: this package is used for bootstrapping fetchurl, and thus
# cannot use fetchpatch! All mutable patches (generated by GitHub or
# cgit) that are needed here should be included directly in Nixpkgs as
# files.

assert !(gnutlsSupport && opensslSupport);
assert !(gnutlsSupport && wolfsslSupport);
assert !(opensslSupport && wolfsslSupport);
assert brotliSupport -> brotli != null;
assert c-aresSupport -> c-ares != null;
assert gnutlsSupport -> gnutls != null;
assert gsaslSupport -> gsasl != null;
assert gssSupport -> libkrb5 != null;
assert http2Support -> nghttp2 != null;
assert http3Support -> nghttp3 != null;
assert http3Support -> ngtcp2 != null;
assert idnSupport -> libidn2 != null;
assert ldapSupport -> openldap != null;
assert opensslSupport -> openssl != null;
assert pslSupport -> libpsl !=null;
assert rtmpSupport -> rtmpdump !=null;
assert scpSupport -> libssh2 != null;
assert wolfsslSupport -> wolfssl != null;
assert zlibSupport -> zlib != null;
assert zstdSupport -> zstd != null;

stdenv.mkDerivation rec {
  pname = "curl";
  version = "7.83.0";

  src = fetchurl {
    urls = [
      "https://curl.haxx.se/download/${pname}-${version}.tar.bz2"
      "https://github.com/curl/curl/releases/download/${lib.replaceStrings ["."] ["_"] pname}-${version}/${pname}-${version}.tar.bz2"
    ];
    sha256 = "sha256-JHx+x1IcQljmVjTlKScNIU/jKWmXHMy3KEXnqkaDH5Y=";
  };

  patches = [
    ./7.79.1-darwin-no-systemconfiguration.patch
  ];

  outputs = [ "bin" "dev" "out" "man" "devdoc" ];
  separateDebugInfo = stdenv.isLinux;

  enableParallelBuilding = true;

  strictDeps = true;

  nativeBuildInputs = [ pkg-config perl ];

  # Zlib and OpenSSL must be propagated because `libcurl.la' contains
  # "-lz -lssl", which aren't necessary direct build inputs of
  # applications that use Curl.
  propagatedBuildInputs = with lib;
    optional brotliSupport brotli ++
    optional c-aresSupport c-ares ++
    optional gnutlsSupport gnutls ++
    optional gsaslSupport gsasl ++
    optional gssSupport libkrb5 ++
    optional http2Support nghttp2 ++
    optionals http3Support [ nghttp3 ngtcp2 ] ++
    optional idnSupport libidn2 ++
    optional ldapSupport openldap ++
    optional opensslSupport openssl ++
    optional pslSupport libpsl ++
    optional rtmpSupport rtmpdump ++
    optional scpSupport libssh2 ++
    optional wolfsslSupport wolfssl ++
    optional zlibSupport zlib ++
    optional zstdSupport zstd;

  # for the second line see https://curl.haxx.se/mail/tracker-2014-03/0087.html
  preConfigure = ''
    sed -e 's|/usr/bin|/no-such-path|g' -i.bak configure
    rm src/tool_hugehelp.c
  '';

  configureFlags = [
      # Build without manual
      "--disable-manual"
      (lib.enableFeature c-aresSupport "ares")
      (lib.enableFeature ldapSupport "ldap")
      (lib.enableFeature ldapSupport "ldaps")
      # The build fails when using wolfssl with --with-ca-fallback
      (lib.withFeature (!wolfsslSupport) "ca-fallback")
      (lib.withFeature http3Support "nghttp3")
      (lib.withFeature http3Support "ngtcp2")
      (lib.withFeature rtmpSupport "librtmp")
      (lib.withFeature zstdSupport "zstd")
      (lib.withFeatureAs brotliSupport "brotli" (lib.getDev brotli))
      (lib.withFeatureAs gnutlsSupport "gnutls" (lib.getDev gnutls))
      (lib.withFeatureAs idnSupport "libidn2" (lib.getDev libidn2))
      (lib.withFeatureAs opensslSupport "openssl" (lib.getDev openssl))
      (lib.withFeatureAs scpSupport "libssh2" (lib.getDev libssh2))
      (lib.withFeatureAs wolfsslSupport "wolfssl" (lib.getDev wolfssl))
    ]
    ++ lib.optional gssSupport "--with-gssapi=${lib.getDev libkrb5}"
       # For the 'urandom', maybe it should be a cross-system option
    ++ lib.optional (stdenv.hostPlatform != stdenv.buildPlatform)
       "--with-random=/dev/urandom"
    ++ lib.optionals stdenv.hostPlatform.isWindows [
      "--disable-shared"
      "--enable-static"
    ] ++ lib.optionals stdenv.isDarwin [
      # Disable default CA bundle, use NIX_SSL_CERT_FILE or fallback to nss-cacert from the default profile.
      # Without this curl might detect /etc/ssl/cert.pem at build time on macOS, causing curl to ignore NIX_SSL_CERT_FILE.
      # https://github.com/curl/curl/issues/8696 - fallback is not supported by HTTP3
      (if http3Support then "--with-ca-bundle=/etc/ssl/certs/ca-certificates.crt" else "--without-ca-bundle")
      "--without-ca-path"
    ];

  CXX = "${stdenv.cc.targetPrefix}c++";
  CXXCPP = "${stdenv.cc.targetPrefix}c++ -E";

  doCheck = false; # expensive, fails

  postInstall = ''
    moveToOutput bin/curl-config "$dev"

    # Install completions
    make -C scripts install
  '' + lib.optionalString scpSupport ''
    sed '/^dependency_libs/s|${lib.getDev libssh2}|${lib.getLib libssh2}|' -i "$out"/lib/*.la
  '' + lib.optionalString gnutlsSupport ''
    ln $out/lib/libcurl.so $out/lib/libcurl-gnutls.so
    ln $out/lib/libcurl.so $out/lib/libcurl-gnutls.so.4
    ln $out/lib/libcurl.so $out/lib/libcurl-gnutls.so.4.4.0
  '';

  passthru = {
    inherit opensslSupport openssl;
    tests = {
      inherit curlpp coeurl;
      haskell-curl = haskellPackages.curl;
      ocaml-curly = ocamlPackages.curly;
      php-curl = phpExtensions.curl;
      pycurl = python3.pkgs.pycurl;
    };
  };

  meta = with lib; {
    description = "A command line tool for transferring files with URL syntax";
    homepage    = "https://curl.se/";
    license = licenses.curl;
    maintainers = with maintainers; [ lovek323 ];
    platforms = platforms.all;
    # Fails to link against static brotli or gss
    broken = stdenv.hostPlatform.isStatic && (brotliSupport || gssSupport);
  };
}
