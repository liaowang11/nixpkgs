{
  lib,
  stdenv,
  fetchgit,
  perl,
  gnutar,
  zlib,
  bzip2,
  xz,
  zstd,
  libmd,
  makeWrapper,
  coreutils,
  autoreconfHook,
  pkg-config,
  diffutils,
  glibc ? !stdenv.hostPlatform.isDarwin,
  darwin,
}:

stdenv.mkDerivation rec {
  pname = "dpkg";
  version = "1.22.11";

  src = fetchgit {
    url = "https://git.launchpad.net/ubuntu/+source/dpkg";
    rev = "applied/${version}";
    hash = "sha256-mKyS0lPTG3ROcw8AhB4IdjNjvZK2YTGV9pbpjz/OLAc=";
  };

  configureFlags = [
    "--disable-dselect"
    "--disable-start-stop-daemon"
    "--with-admindir=/var/lib/dpkg"
    "PERL_LIBDIR=$(out)/${perl.libPrefix}"
    "TAR=${gnutar}/bin/tar"
  ] ++ lib.optional stdenv.hostPlatform.isDarwin "--disable-linker-optimisations";

  enableParallelBuilding = true;

  preConfigure = ''
    # Nice: dpkg has a circular dependency on itself. Its configure
    # script calls scripts/dpkg-architecture, which calls "dpkg" in
    # $PATH. It doesn't actually use its result, but fails if it
    # isn't present, so make a dummy available.
    touch $TMPDIR/dpkg
    chmod +x $TMPDIR/dpkg
    PATH=$TMPDIR:$PATH

    for i in $(find . -name Makefile.in); do
      substituteInPlace $i --replace "install-data-local:" "disabled:" ;
    done

    # Skip check broken when cross-compiling.
    substituteInPlace configure \
      --replace-fail 'as_fn_error $? "cannot find a GNU tar program"' "#"
  '';

  postPatch =
    ''
      patchShebangs --host .

      # Dpkg commands sometimes calls out to shell commands
      substituteInPlace lib/dpkg/dpkg.h \
         --replace '"dpkg-deb"' \"$out/bin/dpkg-deb\" \
         --replace '"dpkg-split"' \"$out/bin/dpkg-split\" \
         --replace '"dpkg-query"' \"$out/bin/dpkg-query\" \
         --replace '"dpkg-divert"' \"$out/bin/dpkg-divert\" \
         --replace '"dpkg-statoverride"' \"$out/bin/dpkg-statoverride\" \
         --replace '"dpkg-trigger"' \"$out/bin/dpkg-trigger\" \
         --replace '"dpkg"' \"$out/bin/dpkg\" \
         --replace '"debsig-verify"' \"$out/bin/debsig-verify\" \
         --replace '"rm"' \"${coreutils}/bin/rm\" \
         --replace '"cat"' \"${coreutils}/bin/cat\" \
         --replace '"diff"' \"${diffutils}/bin/diff\"
    ''
    + lib.optionalString (!stdenv.hostPlatform.isDarwin) ''
      substituteInPlace src/main/help.c \
         --replace '"ldconfig"' \"${glibc.bin}/bin/ldconfig\"
    '';

  buildInputs = [
    perl
    zlib
    bzip2
    xz
    zstd
    libmd
  ] ++ lib.optionals stdenv.hostPlatform.isDarwin [ darwin.apple_sdk.frameworks.CoreServices ];
  nativeBuildInputs = [
    makeWrapper
    perl
    autoreconfHook
    pkg-config
  ];

  postInstall = ''
    for i in $out/bin/*; do
      if head -n 1 $i | grep -q perl; then
        substituteInPlace $i --replace \
          "${perl}/bin/perl" "${perl}/bin/perl -I $out/${perl.libPrefix}"
      fi
    done

    mkdir -p $out/etc/dpkg
    cp -r scripts/t/origins $out/etc/dpkg
  '';

  setupHook = ./setup-hook.sh;

  meta = with lib; {
    description = "Debian package manager";
    homepage = "https://wiki.debian.org/Teams/Dpkg";
    license = licenses.gpl2Plus;
    platforms = platforms.unix;
    maintainers = with maintainers; [ siriobalmelli ];
  };
}
