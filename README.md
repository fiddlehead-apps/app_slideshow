# Sola Slideshow (iOS, Mac)

Auf Deutsch heißt die App **Sola Diashow**.

Native iOS-Version der Web-App [Folder Slideshow](../webapp_slideshow): spielt alle
Bilder eines Ordners, eines Albums aus Fotos (oder ausgewählte Fotos) als Vollbild-Diashow ab. SwiftUI,
keine Abhängigkeiten, iPhone, iPad und Mac, ab iOS 18, Deutsch und Englisch.

* Kein Server, kein Konto – die Bilder verlassen das Gerät nie, außer man schaltet den
  iCloud-Sync ein (aus, solange man ihn nicht einschaltet; dann in die eigene private iCloud).
* Gleiche Bedienung und gleiches Aussehen wie die Web-App.

## Was die App kann

**Start:** *Choose folder* öffnet einen Ordner in Dateien (iCloud Drive, Auf meinem
iPhone, …). Alle Bilder darin und in Unterordnern laufen in Namensreihenfolge
(„img2“ vor „img10“), versteckte Dateien werden übersprungen. *Choose album*
listet die Alben aus Fotos (Mediathek, Favoriten, eigene Alben samt Ordnern, geteilte
Alben, Medienarten wie Selfies oder Panoramen); alle Fotos des gewählten Albums laufen in
der Reihenfolge des Albums, Videos werden übersprungen. *Pick photos or files* fragt per
Menü nach Fotos-Mediathek oder Dateien.

**Abspielen:** Rechter/linker Rand antippen oder wischen = vor/zurück, Mitte =
Bedienelemente ein/aus (blenden sich nach 3 s von selbst aus). Bildschirm bleibt
an. Auf dem iPad mit Tastatur: ← → Leertaste Esc.

**Einstellungen** (Regler-Knopf unten links): Zeit pro Bild (3 s – 1 min), Shuffle,
Bildschirm füllen, Überblenden und – neu gegenüber der Web-App – ob der
**Fortschrittsbalken** unten mitläuft. Jede Diashow merkt sich ihre Einstellungen;
die zuletzt benutzten gelten als Vorgabe für neue (außer dem Bildformat: neue Diashows
zeigen immer alle Bilder).

**Your slideshows:** Jede gestartete Diashow landet in der Liste, sortiert nach
zuletzt gespielt. Ordner und Alben laufen direkt aus Dateien bzw. Fotos (siehe *Kopien*).
Derselbe Ordner oder dasselbe Album noch einmal gewählt öffnet den vorhandenen Eintrag.
Stift = umbenennen, Papierkorb = zweimal tippen zum Löschen.

**Hilfe:** Das „?“ oben rechts erklärt kurz die Bedienung.

## Alben aus Fotos

*Choose album* braucht Lesezugriff auf die ganze Fotos-Mediathek (PhotoKit, Text in
`NSPhotoLibraryUsageDescription`). Beim ersten Mal fragt das System. Hat man auf dem
iPhone nur „Ausgewählte Fotos“ erlaubt, zeigt Fotos keine Alben; die Liste sagt das dann und
bietet *Open Settings* an. Ohne Zugriff erklärt die Startseite, wo man ihn einschaltet (auf
dem Mac: *Systemeinstellungen › Datenschutz & Sicherheit › Fotos*; bei lokal signierten
Builds kann macOS nach jedem Neubau erneut fragen).

Die Diashow merkt sich das Album über seinen `localIdentifier` (Feld `album`) und spielt es
bei jedem Öffnen so ab, wie es gerade ist; Fotos, die nur in iCloud liegen, lädt PhotoKit
nach. Der `localIdentifier` gilt nur auf dem Gerät, auf dem das Album gewählt wurde.

## Kopien

Eine Diashow kann ihre Bilder als verkleinerte Kopien in der App behalten (JPEG, längste
Kante höchstens 2732 px, auf jedem Gerät gleich). Ob sie das tut, hängt von der Quelle ab:

| Quelle | Kopie | Abspielen |
| --- | --- | --- |
| Ordner | wahlweise, Standard aus | direkt aus dem Ordner (Bookmark), mit Kopie aus der Kopie |
| Album aus Fotos | wahlweise, Standard aus | direkt aus dem Album, mit Kopie aus der Kopie |
| einzeln gewählte Fotos/Dateien | immer | aus der Kopie (lassen sich später nicht noch einmal öffnen) |
| aus iCloud empfangen, oder von vor dieser Version | immer | aus der Kopie |

* **Einschalten:** in den Einstellungen der laufenden Diashow *Keep a copy on this device*.
  Ab 1000 Bildern fragt die App vorher und nennt den ungefähren Platzbedarf.
* **Aktualisieren:** Eine Kopie ist ein Schnappschuss. *Update copy* (Einstellungen der
  Diashow oder langes Drücken auf den Eintrag) legt sie aus dem aktuellen Inhalt neu an.
* **Anzeige und Löschen:** Unter jedem Eintrag mit Kopie steht *Copy on this device: 86 MB*
  mit *Delete copy*. Bei Ordnern und Alben bleibt die Diashow danach in der Liste; gibt es
  sie nur als Kopie, sagt die Rückfrage, dass die ganze Diashow gelöscht wird.
* **Reihenfolge:** Kopien entstehen nacheinander. Eine neue Auswahl bricht eine laufende
  Kopie nicht ab, sondern stellt sich an („Waiting to be saved“).
* **Unterbrechungen:** Nach dem Verlassen der App läuft das Kopieren die Zeit weiter, die
  iOS gewährt. Wurde es abgeschnitten, fängt es beim nächsten Start für Ordner und Alben von
  vorn an; bis dahin spielt die Diashow aus der Quelle. Bei einzeln gewählten Fotos bleibt
  das Gespeicherte („Only 37 of 100 images were saved“).
* **Hänger:** Ein Bild, das nach 3 Minuten nicht da ist (kein Netz, iCloud-Download hängt),
  wird ausgelassen. Am Ende meldet die Startseite, wie viele Bilder fehlen. Lässt sich gar
  nichts lesen oder ist der Speicher voll, läuft ein Ordner/Album ohne Kopie weiter.
* **Derselbe Ordner** wird am Pfad erkannt, nicht mehr am Namen. Nur Einträge ohne
  gemerkten Ordner (alte, oder von einem anderen Gerät) werden noch über den Namen
  zugeordnet. Versteckte Diashows übernimmt eine neue Auswahl nie.
* **Backups:** Der Ordner `Slideshows` ist von Geräte- und iCloud-Backups ausgenommen. Auf
  ein neues Gerät kommen Diashows über den iCloud-Sync.
* **Liste:** `library.json` wird beim Start nach `library.backup.json` gesichert. Ist sie
  beschädigt, lädt die App die Sicherung (die kaputte Datei bleibt als
  `library.damaged.json` liegen); ist sie nur gesperrt, wird sie nicht überschrieben.

## iCloud-Sync

Standardmäßig aus. Eingeschaltet wird er in der Hilfe („?“) unter *iCloud*. Dann gehen über
die private CloudKit-Datenbank des Nutzers (CKSyncEngine, eine Record-Zone „Slideshows“):

* jede Diashow **mit Kopie** (Name, Ordnername, Dateinamen, Einstellungen, versteckt, zuletzt gespielt),
* jede gespeicherte Kopie als eigener Record mit Asset,
* die Vorgaben für neue Diashows.

Diashows ohne Kopie bleiben auf dem Gerät, das ihren Ordner oder ihr Album hat. Wird die
Kopie gelöscht, verschwindet die Diashow aus iCloud und von den anderen Geräten (die
Rückfrage sagt das). Kommt eine solche Löschung auf einem Gerät an, das den Ordner oder das
Album selbst hat, bleibt die Diashow dort ohne Kopie erhalten.

Inhalte liegen in `encryptedValues` bzw. als Assets, also verschlüsselt. Vorschaubilder,
Größen und wie viele Bilder schon da sind, rechnet jedes Gerät selbst aus; solange Bilder
noch kommen, steht in der Liste „Wird aus iCloud geladen: 12 von 80“. Hochgeladen wird eine
Diashow erst, wenn alle Kopien fertig sind. Konflikte: die neuere Seite gewinnt, getrennt
für die Details (`modified`) und die Bilder (`content`, dazu Anzahl und Dateinamen). Wird
der Sync ohne Verbindung eingeschaltet, lädt die App das Vorhandene hoch, sobald der erste
Abgleich geklappt hat.

Ausschalten fragt, ob die Daten in iCloud bleiben oder gelöscht werden; auf dem Gerät bleibt
alles. Abmelden, Account-Wechsel oder in iCloud gelöschte Daten schalten den Sync ebenfalls
aus, ohne lokal etwas zu löschen.

## Versteckte Diashows

* **Verstecken:** Eine Diashow in *Your slideshows* **fünfmal schnell antippen**
  → Rückfrage → sie verschwindet aus der Liste. (Ein einzelner Tipp startet sie
  wie gewohnt, mit 0,3 s Verzögerung, weil die App erst auf weitere Tipps wartet.)
* **Ansehen:** In der Hilfe den Absatz **„Private“** fünfmal antippen → Face ID
  (Fallback: Gerätecode) → Liste der versteckten Diashows. Dort lassen sie sich
  abspielen, umbenennen, löschen oder per Auge-Symbol zurückholen.
* Verlässt man die App, wird die Hilfe geschlossen; danach ist wieder Face ID
  nötig. Läuft gerade eine versteckte Diashow, zeigt der App-Umschalter nur Schwarz.
* Ohne eingerichteten Gerätecode passiert beim fünften Tipp nichts.

## Sprachen

Englisch (Ausgangssprache) und Deutsch. Die App folgt der Sprache des Geräts.

* Alle Oberflächentexte stehen in `SolaSlideshow/Localizable.xcstrings`, der
  Face-ID-Hinweis in `SolaSlideshow/InfoPlist.xcstrings` (String Catalogs). Jeder
  Eintrag hat einen Kommentar mit Kontext für Übersetzer.
* Der englische Text ist zugleich der Schlüssel. Pluralformen („1 image /
  8 images“) laufen über Plural-Varianten im Catalog, nicht über `if` im Code.
* Neue Texte im Code immer als Literal in `Text`/`Button`/`Label` schreiben
  oder über `String(localized:)` erzeugen, nie als zusammengesetzten `String`.
  Xcode übernimmt sie beim Bauen automatisch in den Catalog.

**Weitere Sprache hinzufügen:** In Xcode *Project › Info › Localizations › +*,
dann im Catalog übersetzen. Oder für Übersetzer eine XLIFF-Datei erzeugen und
die fertige wieder einspielen:

```bash
xcodebuild -exportLocalizations -project SolaSlideshow.xcodeproj -scheme SolaSlideshow -localizationPath /tmp/slideshow-loc -exportLanguage fr -derivedDataPath /tmp/slideshow-build
```

```bash
xcodebuild -importLocalizations -project SolaSlideshow.xcodeproj -localizationPath /tmp/slideshow-loc/fr.xcloc
```

Im Simulator eine Sprache erzwingen, ohne das Gerät umzustellen: in Xcode unter
*Scheme › Run › Options › App Language*.

## Bauen

```bash
open SolaSlideshow.xcodeproj
```

Team und Bundle-ID (`eu.fiddlehead.sola.slideshow`) kommen aus `Config/Config.xcconfig`,
nicht aus dem Projekt. Ein anderes Team setzt man als `SOLA_TEAM` in
`../sola-local.xcconfig` (siehe *iCloud*). Für den Simulator geht es auch ohne Team:

```bash
xcodebuild -project SolaSlideshow.xcodeproj -scheme SolaSlideshow -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/slideshow-build build
```

`-derivedDataPath` außerhalb von `~/Documents` halten: iCloud hängt dort
Finder-Attribute an, an denen die Code-Signatur scheitert.

### Aufs eigene iPhone ohne bezahlten Developer-Account

Das Projekt ist mit dem kostenlosen Personal Team (`Z4Z62632W2`) signiert. So
signierte Apps laufen **7 Tage**, danach einfach neu bauen und installieren –
die gespeicherten Diashows bleiben erhalten. iPhone per Kabel anschließen,
entsperren, dann:

```bash
xcodebuild -project SolaSlideshow.xcodeproj -scheme SolaSlideshow -configuration Release -destination 'id=<DEVICE-ID>' -derivedDataPath /tmp/slideshow-device -allowProvisioningUpdates build
```

```bash
xcrun devicectl device install app --device <DEVICE-ID> "/tmp/slideshow-device/Build/Products/Release-iphoneos/Sola Slideshow.app"
```

Beim allerersten Mal auf dem iPhone dem Profil vertrauen: *Einstellungen ›
Allgemein › VPN & Geräteverwaltung › Apple-ID › Vertrauen*. Der Entwicklermodus
(*Datenschutz & Sicherheit › Entwicklermodus*) muss an sein.

### iCloud

iCloud-Sync braucht ein bezahltes Developer-Team; das Personal Team kann iCloud und Push
nicht signieren. Deshalb ist es ein Build-Schalter in `Config/Config.xcconfig`:
`SOLA_ICLOUD = NO` (Standard) baut ohne iCloud-Entitlements, der Schalter in der App sagt
dann, dass dieser Build nicht synchronisiert. Mit dem fiddlehead-Team neben den Repos eine
`sola-local.xcconfig` anlegen (gilt für alle Sola-Apps, auch in Xcode):

```
SOLA_TEAM = <Team-ID>
SOLA_ICLOUD = YES
```

oder einmalig `../build-sola-apps.sh --icloud`. Vor TestFlight/App Store im CloudKit
Dashboard das Schema nach Production deployen.

### Auf dem Mac (Mac Catalyst)

Dasselbe Target baut auch eine echte Mac-App. Sie ist lokal signiert
(„Sign to Run Locally“), braucht also keinen Account und läuft ohne
7-Tage-Grenze – allerdings nur auf dem Mac, auf dem sie gebaut wurde.

```bash
xcodebuild -project SolaSlideshow.xcodeproj -scheme SolaSlideshow -configuration Release -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath /tmp/slideshow-mac build
```

```bash
ditto "/tmp/slideshow-mac/Build/Products/Release-maccatalyst/Sola Slideshow.app" ~/Applications/"Sola Slideshow.app"
```

Die Mac-App läuft in der App Sandbox (Pflicht für den Mac App Store). Sie darf nur lesen,
was man in ihr auswählt, sich Ordner per Bookmark merken und die Fotos-Mediathek lesen; ins
Netz darf nur der iCloud-Build. Die Rechte stehen in `Config/SolaSlideshow-Mac.entitlements`
bzw. `…-Mac-iCloud.entitlements`.

Die Daten liegen damit im Container:
`~/Library/Containers/eu.fiddlehead.sola.slideshow/Data/Library/Application Support/eu.fiddlehead.sola.slideshow/Slideshows`.
Daten aus Builds vor der Sandbox (`~/Library/Application Support/eu.fiddlehead.sola.slideshow`)
soll macOS beim ersten Start dorthin umziehen (`SolaSlideshow/container-migration.plist`).
Statt Face ID fragt das Versteck nach Touch ID bzw. dem Mac-Passwort. Pfeiltasten,
Leertaste und Esc steuern die Diashow, Vollbild über den grünen Fensterknopf.

App-Icon neu erzeugen (gleiches Motiv wie die Web-App, braucht Pillow):

```bash
python3 tools/make_icon.py
```

## Tests und Build-Check

```bash
./build.sh --test
```

lässt die Unit-Tests im Simulator laufen (`SolaSlideshowTests/`, Swift Testing): das
Datenmodell samt alten gespeicherten Listen, welche Seite beim iCloud-Abgleich gewinnt
(`Show.merged`), die Reihenfolge beim Kopieren (`CopyQueue`) und das Wiedererkennen von
Ordnern und Alben (`Library.match`).

```bash
./build.sh --mac-check
```

kompiliert die Mac-App ohne Signatur. `.github/workflows/build.yml` macht bei jedem Push,
der die App betrifft, beides plus den Simulator-Build auf einem Mac-Runner von GitHub.

## Aufbau

| Datei | Inhalt |
| --- | --- |
| `SolaSlideshowApp.swift` | Einstieg, Auswahl von Ordner/Dateien/Fotos, Zusammenspiel der Bildschirme |
| `StartView.swift` | Startseite mit Liste, Warte-Hinweis, Verstecken-Rückfrage |
| `ShowRow.swift` | Listeneintrag, Mehrfach-Tipp-Erkennung |
| `PlayerView.swift` / `Player.swift` | Diashow: Anzeige, Gesten, Takt, Vorladen, Einstellungsblatt |
| `Library.swift` | Liste der Diashows (`Application Support/Slideshows`), Ordner/Alben wieder öffnen, Kopien (Warteschlange), Records für iCloud |
| `CloudSync.swift` / `CloudSyncToggle.swift` | iCloud-Sync (CKSyncEngine), Schalter mit Status; gleiche Dateien wie in Sola Birthdays |
| `Images.swift` | Ordner durchsuchen und per Bookmark merken, iCloud-Dateien laden, verkleinern (ImageIO) |
| `Albums.swift` | Alben aus Fotos (PhotoKit): Zugriff, Album-Liste, Bilder laden |
| `HelpView.swift` | Hilfe, Face-ID-Entsperren, versteckte Diashows |
| `Models.swift` / `Theme.swift` | Datenmodell samt Abgleich mit dem iCloud-Record, Farben wie in der Web-App |
| `CopyQueue.swift` | Reihenfolge, in der Diashows ihre Kopien bekommen |
| `SolaSlideshowTests/` | Unit-Tests |
| `Localizable.xcstrings` / `InfoPlist.xcstrings` | Texte auf Englisch und Deutsch |
| `Config/` | `Config.xcconfig` (Bundle-ID, Team, iCloud-Schalter), Info.plist, Entitlements (iCloud, Mac-Sandbox) |
