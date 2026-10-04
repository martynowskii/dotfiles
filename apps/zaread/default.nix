# zaread — открывает документ в zathura, отрендерив его в PDF и положив
# результат в ~/.cache/zaread. https://github.com/paoloap/zaread
#
# В nixpkgs его нет, поэтому собираем здесь.
{ lib
, stdenvNoCC
, fetchFromGitHub
, makeWrapper
, zathura
, libreoffice-still
, file
, coreutils
, md2pdf
, typst
, calibre
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "zaread";
  version = "1.5.0";

  src = fetchFromGitHub {
    owner = "paoloap";
    repo = "zaread";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Q6Fs9WNr/xm1t0rhWtxriO9ifEcUTdMCBNpgLMvJCDE=";
  };

  nativeBuildInputs = [ makeWrapper ];

  # Первая цель в Makefile — install с DEST=/usr, так что безцелевой make
  # из стандартной сборки лезет мимо store.
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    make install DEST=$out
    wrapProgram $out/bin/zaread --prefix PATH : ${lib.makeBinPath [
      zathura libreoffice-still file coreutils md2pdf typst calibre
    ]}
    runHook postInstall
  '';

  meta = {
    description = "Лёгкий просмотрщик документов поверх zathura";
    homepage = "https://github.com/paoloap/zaread";
    license = lib.licenses.gpl3Only;
    mainProgram = "zaread";
    platforms = lib.platforms.unix;
  };
})
