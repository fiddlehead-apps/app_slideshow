# Slideshow (iOS)

Native iOS-Version der Web-App [Folder Slideshow](../webapp_slideshow): spielt alle
Bilder eines Ordners (oder ausgewählte Fotos) als Vollbild-Diashow ab. SwiftUI,
keine Abhängigkeiten, iPhone und iPad, ab iOS 18, Deutsch und Englisch.

* Kein Server, kein Konto – die Bilder verlassen das Gerät nie.
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

* Alle Oberflächentexte stehen in `Slideshow/Localizable.xcstrings`, der
  Face-ID-Hinweis in `Slideshow/InfoPlist.xcstrings` (String Catalogs). Jeder
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
xcodebuild -exportLocalizations -project Slideshow.xcodeproj -scheme Slideshow -localizationPath /tmp/slideshow-loc -exportLanguage fr -derivedDataPath /tmp/slideshow-build
```

```bash
xcodebuild -importLocalizations -project Slideshow.xcodeproj -localizationPath /tmp/slideshow-loc/fr.xcloc
```

Im Simulator eine Sprache erzwingen, ohne das Gerät umzustellen: in Xcode unter
*Scheme › Run › Options › App Language*.

## Bauen

```bash
open Slideshow.xcodeproj
```

In Xcode unter *Signing & Capabilities* das eigene Team wählen, dann auf dem
iPhone ausführen. Für den Simulator geht es auch ohne Team:

```bash
xcodebuild -project Slideshow.xcodeproj -scheme Slideshow -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/slideshow-build build
```

`-derivedDataPath` außerhalb von `~/Documents` halten: iCloud hängt dort
Finder-Attribute an, an denen die Code-Signatur scheitert.

### Aufs eigene iPhone ohne bezahlten Developer-Account

Das Projekt ist mit dem kostenlosen Personal Team (`Z4Z62632W2`) signiert. So
signierte Apps laufen **7 Tage**, danach einfach neu bauen und installieren –
die gespeicherten Diashows bleiben erhalten. iPhone per Kabel anschließen,
entsperren, dann:

```bash
xcodebuild -project Slideshow.xcodeproj -scheme Slideshow -configuration Release -destination 'id=00008150-000655C92E20401C' -derivedDataPath /tmp/slideshow-device -allowProvisioningUpdates build
```

```bash
xcrun devicectl device install app --device 00008150-000655C92E20401C /tmp/slideshow-device/Build/Products/Release-iphoneos/Slideshow.app
```

Beim allerersten Mal auf dem iPhone dem Profil vertrauen: *Einstellungen ›
Allgemein › VPN & Geräteverwaltung › Apple-ID › Vertrauen*. Der Entwicklermodus
(*Datenschutz & Sicherheit › Entwicklermodus*) muss an sein.

App-Icon neu erzeugen (gleiches Motiv wie die Web-App, braucht Pillow):

```bash
python3 tools/make_icon.py
```

## Aufbau

| Datei | Inhalt |
| --- | --- |
| `SlideshowApp.swift` | Einstieg, Auswahl von Ordner/Dateien/Fotos, Zusammenspiel der Bildschirme |
| `StartView.swift` | Startseite mit Liste, Warte-Hinweis, Verstecken-Rückfrage |
| `ShowRow.swift` | Listeneintrag, Mehrfach-Tipp-Erkennung |
| `PlayerView.swift` / `Player.swift` | Diashow: Anzeige, Gesten, Takt, Vorladen, Einstellungsblatt |
| `Library.swift` | Gespeicherte Diashows (`Application Support/Slideshows`), Kopieren im Hintergrund |
| `Images.swift` | Ordner durchsuchen, iCloud-Dateien laden, verkleinern (ImageIO) |
| `HelpView.swift` | Hilfe, Face-ID-Entsperren, versteckte Diashows |
| `Models.swift` / `Theme.swift` | Datenmodell, Farben wie in der Web-App |
| `Localizable.xcstrings` / `InfoPlist.xcstrings` | Texte auf Englisch und Deutsch |
