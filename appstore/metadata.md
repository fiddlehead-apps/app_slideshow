# App Store Connect – Sola Diashow / Sola Slideshow

Texte zum Einfügen in App Store Connect. Zeichenlimits sind geprüft (Name/Untertitel 30, Werbetext 170, Keywords 100 Bytes, Beschreibung 4000).

## Allgemein

| Feld | Wert |
| --- | --- |
| Bundle-ID | `eu.fiddlehead.sola.slideshow` |
| SKU | `eu.fiddlehead.sola.slideshow` |
| Plattformen | iPhone, iPad, Mac (Mac Catalyst – im Mac App Store als eigene Plattform in derselben App) |
| Primärsprache | Deutsch (weitere: Englisch) |
| Kategorie | Foto und Video (Photo & Video) |
| Zweite Kategorie | Lifestyle |
| Preis | Kostenlos |
| Copyright | 2026 Christoph Schneider |
| Support-URL | https://fiddlehead.eu/sola-slideshow/support/ |
| Marketing-URL | https://fiddlehead.eu/sola-slideshow/ |
| Datenschutz-URL | https://fiddlehead.eu/sola-slideshow/privacy/ |
| Verschlüsselung | Im Info.plist erledigt (`ITSAppUsesNonExemptEncryption = NO`) |

## App-Datenschutz

Datenschutzangaben: „Daten werden nicht erfasst“ („Data Not Collected“). Die App schickt nichts an eigene Server; iCloud-Sync (nur wenn eingeschaltet) läuft über die private iCloud-Datenbank der Nutzerin bzw. des Nutzers, darauf hast du keinen Zugriff – das zählt bei Apple nicht als Datenerfassung durch dich.

## Altersfreigabe

Alle Fragen „Nein/Keine“ → 4+. Die App zeigt nur Bilder, die die Nutzerin bzw. der Nutzer selbst auswählt.

## Deutsch

**Name** (12/30)

Sola Diashow

**Untertitel / Subtitle** (30/30)

Deine Fotos als ruhige Diashow

**Werbetext / Promotional text** (100/170)

Wähl einen Ordner oder ein paar Fotos – und lehn dich zurück. Deine Bilder verlassen dein Gerät nie.

**Keywords** (99/100)

```
foto,bilderrahmen,ordner,bilder,vollbild,zufall,überblenden,galerie,präsentation,mac,ipad,digital
```

**Beschreibung / Description** (1126/4000)

```
Sola Diashow zeigt deine Fotos als ruhige, schöne Vollbild-Diashow.

Wähl einen Ordner in der Dateien-App – iCloud Drive, „Auf meinem iPhone“ oder ein anderer Speicherort – und alle Bilder darin und in den Unterordnern laufen der Reihe nach ab. Oder such dir einzelne Fotos aus deiner Mediathek aus.

SO, WIE DU ES MAGST
• Zeit pro Bild von 3 Sekunden bis 1 Minute.
• Zufallsreihenfolge, Überblenden und Bildschirm füllen.
• Ein dezenter Fortschrittsbalken, wenn du ihn willst.
• Antippen oder wischen für vor und zurück, auf dem iPad auch mit Tastatur.
• Der Bildschirm bleibt an, solange die Diashow läuft – ideal als digitaler Bilderrahmen.

DEINE DIASHOWS
• Jede Diashow merkt sich ihre Einstellungen und bleibt in deiner Liste.
• Die App speichert verkleinerte Kopien, danach braucht sie den Ordner nicht mehr.
• Diashows lassen sich umbenennen, löschen oder verstecken.

DEINE BILDER BLEIBEN BEI DIR
• Kein Konto, keine Werbung, kein Tracking.
• Alles bleibt auf deinem Gerät. Synchronisierung über deine eigene iCloud nur, wenn du sie einschaltest.

Für iPhone, iPad und Mac. Sola Diashow ist kostenlos und Open Source.
```

## English

**Name** (14/30)

Sola Slideshow

**Untertitel / Subtitle** (30/30)

Calm slideshows of your photos

**Werbetext / Promotional text** (84/170)

Pick a folder or a few photos – and sit back. Your pictures never leave your device.

**Keywords** (92/100)

```
photo,picture,frame,folder,fullscreen,shuffle,crossfade,gallery,presentation,images,mac,ipad
```

**Beschreibung / Description** (983/4000)

```
Sola Slideshow shows your photos as a calm, beautiful full-screen slideshow.

Choose a folder in the Files app – iCloud Drive, On My iPhone or any other location – and every image in it and its subfolders plays in order. Or pick individual photos from your library.

THE WAY YOU LIKE IT
• Time per image from 3 seconds to 1 minute.
• Shuffle, crossfade and fill the screen.
• A subtle progress bar, if you want one.
• Tap or swipe to go forward and back; on iPad, use the keyboard too.
• The screen stays on while the slideshow plays – perfect as a digital photo frame.

YOUR SLIDESHOWS
• Each slideshow remembers its settings and stays in your list.
• The app keeps resized copies, so it no longer needs the folder afterwards.
• Rename, delete or hide slideshows.

YOUR PICTURES STAY WITH YOU
• No account, no ads, no tracking.
• Everything stays on your device. Sync through your own iCloud only if you turn it on.

For iPhone, iPad and Mac. Sola Slideshow is free and open source.
```

## Hinweise für die Prüfung (App Review Information)

Anmeldedaten: keine (Haken bei „Anmeldung erforderlich“ weglassen). Kontakt: dein Name, Telefonnummer und support@fiddlehead.eu.

```
Keine Anmeldung nötig. „Fotos oder Dateien wählen“ antippen und ein paar Fotos aus der Mediathek wählen; die Diashow startet sofort. Mitte antippen blendet die Bedienelemente ein, das „?“ erklärt die Bedienung.

Versteckte Diashows (dokumentierte Datenschutzfunktion): Eine Diashow in der Liste fünfmal schnell antippen versteckt sie; angezeigt werden sie, indem man in der Hilfe („?“) den Absatz „Privat“ fünfmal antippt und mit Face ID / Touch ID bzw. Gerätecode bestätigt.

iCloud-Sync ist standardmäßig aus und wird in der Hilfe („?“) eingeschaltet.

English: No sign-in needed. Tap "Pick photos or files", choose a few photos and the slideshow starts. Tap the center to show the controls; "?" explains everything. Hidden slideshows (a documented privacy feature): tapping a slideshow five times quickly hides it; to see hidden slideshows, open help ("?"), tap the "Private" paragraph five times and confirm with Face ID / Touch ID or the device passcode. iCloud sync is off by default.
```

## Screenshots

In `appstore/screenshots/<sprache>/`, in der Reihenfolge der Nummern hochladen. Größen: iPhone 6,9" (1320 × 2868), iPad 13" (2064 × 2752). Für den Mac App Store braucht es zusätzlich Mac-Screenshots (z. B. 2880 × 1800); die sind noch nicht dabei.

Entstanden im Simulator mit Demodaten: Debug-Build mit dem Startargument `-demoData YES` (siehe `DemoData.swift`; im Release-Build nicht enthalten). Alle Namen und Bilder sind erfunden.

- `screenshots/de/ipad-1.png`
- `screenshots/de/ipad-2.png`
- `screenshots/de/iphone-1.png`
- `screenshots/de/iphone-2.png`
- `screenshots/de/iphone-3.png`
- `screenshots/en/ipad-1.png`
- `screenshots/en/ipad-2.png`
- `screenshots/en/iphone-1.png`
- `screenshots/en/iphone-2.png`
- `screenshots/en/iphone-3.png`

## Vor dem Einreichen

- In der Datenschutzerklärung auf fiddlehead.eu steht noch `TODO: ladungsfähige Anschrift` bei „Verantwortlich“ – Adresse ergänzen (DSGVO).
- In App Store Connect unter Business den **EU-Händlerstatus (DSA)** angeben, sonst erscheint die App in der EU nicht.
- Archiv bauen: Xcode → Product → Archive (Release, Schema der App) → Distribute App → App Store Connect.
- **CloudKit-Schema auf Production deployen** (CloudKit Console → Container der Diashow → Deploy Schema Changes).
- Mac-Version (Mac Catalyst): in App Store Connect die Plattform macOS hinzufügen, eigenes Archiv für „Any Mac“ hochladen und Mac-Screenshots ergänzen – oder vorerst nur iOS veröffentlichen.
