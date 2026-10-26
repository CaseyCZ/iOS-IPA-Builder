# IPA Control (první testovací verze)

Nativní iOS aplikace ve SwiftUI. Je to první klient našeho budoucího osobního systému pro instalaci a obnovení IPA.

## Co funguje v této verzi

- Přidání a odstranění HTTPS URL zdrojů ve formátu AltStore Classic JSON.
- Načtení názvu zdroje, aplikací, verzí a odkazů na IPA.
- Uložení přidaných zdrojů a adresy vlastního serveru v zařízení.
- Test dostupnosti serveru přes `GET /health` (HTTP 200).
- Připravená záložka „Moje aplikace“ a přehled limitů free Apple účtu.

## Co zatím záměrně nefunguje

- Podepisování a instalace IPA.
- Obnova provisioning profilů.
- Zjišťování všech nainstalovaných aplikací nebo jejich skutečné platnosti.

Tyto funkce vyžadují samostatnou podpisovou službu a prověřený mechanismus instalace přes spárovaný iPhone. Tlačítka jsou proto označena jako nedostupná; klient nevytváří falešný dojem instalace.

## Sestavení

Projekt `IPAControl.xcodeproj` obsahuje scheme `IPAControl` (automaticky sdílené podle projektu). Lze jej sestavit přes `CaseyCZ/iOS-IPA-Builder` s:

- `source_repo`: `CaseyCZ/iOS-IPA-Builder`
- `project_path`: `apps/IPA-Control`
- `project_type`: `xcode` nebo `auto`
- `xcode_runner`: `macos-latest`
- `build_mode`: `unsigned`
- `scheme`: `IPAControl` (je-li vyžadováno)
- `output_repo`: existující cílový repozitář s odpovídajícími právy `OUTPUT_TOKEN` (lze použít i tento repozitář, pokud to chceš veřejně publikovat)

Výstupem je **nepodepsané IPA**. První instalace stále vyžaduje funkční sideloadovací nástroj přes Windows + USB-C; samotné nahrání na web neumožní instalaci zdarma podepsané aplikace.

## Bezpečnost

V aplikaci nejsou uložená Apple ID hesla, soukromé klíče ani párovací soubory. Přijímá jen HTTPS zdroje a serverové URL. Zdroje JSON jsou nedůvěryhodný obsah a aplikace z nich nic automaticky neinstaluje.
