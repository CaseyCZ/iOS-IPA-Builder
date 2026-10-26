# Aplikace

Zdrojové kódy aplikací spravované spolu s IPA Builderem.

| Aplikace | Umístění | Stav |
| --- | --- | --- |
| IPA Control | [`IPA-Control/`](IPA-Control/) | První testovací klient, bez podepisování a instalace |

Builder zůstává samostatným workflow v `.github/workflows/build-ios.yml`.
Pro sestavení IPA Control vyber `source_repo = CaseyCZ/iOS-IPA-Builder`, `project_path = apps/IPA-Control` a `build_mode = unsigned`.

Sestavení nepodepsaného IPA nespotřebuje žádný provisioning profil ani App ID. Test skutečné instalace bude zvláštním, vědomě spuštěným krokem.
