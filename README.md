# Sola Slideshow (iOS, Mac)

Auf Deutsch heißt die App **Sola Diashow**.

Native iOS-Version der Web-App [Folder Slideshow](../webapp_slideshow): spielt alle
Bilder eines Ordners (oder ausgewählte Fotos) als Vollbild-Diashow ab. SwiftUI,
keine Abhängigkeiten, iPhone, iPad und Mac, ab iOS 18, Deutsch und Englisch.

* Kein Server, kein Konto – die Bilder verlassen das Gerät nie, außer man schaltet den
  iCloud-Sync ein (aus, solange man ihn nicht einschaltet; dann in die eigene private iCloud).
* Gleiche Bedienung und gleiches Aussehen wie die Web-App.

## Was die App kann

**Start:** *Choose folder* öffnet einen Ordner in Dateien (iCloud Drive, Auf meinem
iPhone, …). Alle Bilder darin und in Unterordnern laufen in Namensreihenfolge
(„img2“ vor „img10“), versteckte Dateien werden übersprungen. *Pick photos or
files* fragt per Menü nach Fotos-Mediathek oder Dateien.

**Abspielen:** Rechter/linker Rand antippen oder wischen = vor/zurück, Mitte =
Bedienelemente ein/aus (blenden sich nach 3 s von selbst aus). Bildschirm bleibt
an. Auf dem iPad mit Tastatur: ← → Leertaste Esc.

**Einstellungen** (Regler-Knopf unten links): Zeit pro Bild (3 s – 1 min), Shuffle,
Bildschirm füllen, Überblenden und – neu gegenüber der Web-App – ob der
**Fortschrittsbalken** unten mitläuft. Jede Diashow merkt sich ihre Einstellungen;
die zuletzt benutzten gelten als Vorgabe für neue.

**Your slideshows:** Jede gestartete Diashow landet in der Liste, sortiert nach
zuletzt gespielt. Wie in der Web-App werden verkleinerte Kopien
(Bildschirmauflösung, max. 2732 px) gespeichert, danach braucht es den Ordner
nicht mehr. Derselbe Ordner noch einmal gewählt ersetzt den alten Eintrag.
Stift = umbenennen, Papierkorb = zweimal tippen zum Löschen.

**Hilfe:** Das „?“ oben rechts erklärt kurz die Bedienung.

## iCloud-Sync

Standardmäßig aus. Eingeschaltet wird er in der Hilfe („?“) unter *iCloud*. Dann gehen über
die private CloudKit-Datenbank des Nutzers (CKSyncEngine, eine Record-Zone „Slideshows“):

* jede Diashow (Name, Ordner, Dateinamen, Einstellungen, versteckt, zuletzt gespielt),
* jede gespeicherte Kopie als eigener Record mit Asset,
* die Vorgaben für neue Diashows.

Inhalte liegen in `encryptedValues` bzw. als Assets, also verschlüsselt. Vorschaubilder,
Größen und wie viele Bilder schon da sind, rechnet jedes Gerät selbst aus; solange Bilder
noch kommen, steht in der Liste „Wird aus iCloud geladen: 12 von 80“. Hochgeladen wird eine
Diashow erst, wenn alle Kopien fertig sind. Konflikte: die neuere Seite gewinnt (Details
über `modified`, Bilder über `content`).

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
xcodebuild -project SolaSlideshow.xcodeproj -scheme SolaSlideshow -configuration Release -destination 'id=00008150-000655C92E20401C' -derivedDataPath /tmp/slideshow-device -allowProvisioningUpdates build
```

```bash
xcrun devicectl device install app --device 00008150-000655C92E20401C "/tmp/slideshow-device/Build/Products/Release-iphoneos/Sola Slideshow.app"
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

Auf dem Mac liegen die Daten unter
`~/Library/Application Support/eu.fiddlehead.sola.slideshow/Slideshows` (Diashows aus
Builds mit der alten Bundle-ID `org.christophschneider.slideshow` zieht die App beim
ersten Start dorthin um).
Statt Face ID fragt das Versteck nach Touch ID bzw. dem Mac-Passwort. Pfeiltasten,
Leertaste und Esc steuern die Diashow, Vollbild über den grünen Fensterknopf.

App-Icon neu erzeugen (gleiches Motiv wie die Web-App, braucht Pillow):

```bash
python3 tools/make_icon.py
```

## Aufbau

| Datei | Inhalt |
| --- | --- |
| `SolaSlideshowApp.swift` | Einstieg, Auswahl von Ordner/Dateien/Fotos, Zusammenspiel der Bildschirme |
| `StartView.swift` | Startseite mit Liste, Warte-Hinweis, Verstecken-Rückfrage |
| `ShowRow.swift` | Listeneintrag, Mehrfach-Tipp-Erkennung |
| `PlayerView.swift` / `Player.swift` | Diashow: Anzeige, Gesten, Takt, Vorladen, Einstellungsblatt |
| `Library.swift` | Gespeicherte Diashows (`Application Support/Slideshows`), Kopieren im Hintergrund, Records für iCloud |
| `CloudSync.swift` / `CloudSyncToggle.swift` | iCloud-Sync (CKSyncEngine), Schalter mit Status; gleiche Dateien wie in Sola Birthdays |
| `Images.swift` | Ordner durchsuchen, iCloud-Dateien laden, verkleinern (ImageIO) |
| `HelpView.swift` | Hilfe, Face-ID-Entsperren, versteckte Diashows |
| `Models.swift` / `Theme.swift` | Datenmodell, Farben wie in der Web-App |
| `Localizable.xcstrings` / `InfoPlist.xcstrings` | Texte auf Englisch und Deutsch |
| `Config/` | `Config.xcconfig` (Bundle-ID, Team, iCloud-Schalter), Info.plist, iCloud-Entitlements |
