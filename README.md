# Branch – Datei-Explorer für macOS

Eine native Mac-Dateiverwaltung mit Windows-Explorer-orientierter Bedienung,
Verzeichnisbaum, optionaler zweiter Dateiansicht und dem animierten Helfer **Botti**.
Die Oberfläche folgt dem hellen oder dunklen Systemdesign.

## Download und Installation

Die fertige App findest du unter [Releases](https://github.com/maildienste-cell/branch-file-manager/releases).
ZIP entpacken und **Branch.app** in den Programme-Ordner ziehen.

- **Apple Silicon (M1 oder neuer), macOS 14 oder neuer.** Keine Intel-Version.
- Die App ist lokal/ad hoc signiert, **nicht mit Apple Developer ID signiert oder notarisiert**.
  macOS kann den ersten Start blockieren. Prüfe die Herkunft; die Freigabe erfolgt gegebenenfalls
  unter **Systemeinstellungen → Datenschutz & Sicherheit → Dennoch öffnen**.
- Kein Installer, kein Administratorzugriff zum normalen Betrieb und kein Cloud-Konto nötig.
- Die lokale KI setzt macOS 26 und ein auf dem Gerät verfügbares Apple-Intelligence-Modell voraus.
  Ohne dieses Modell bleibt die einfache lokale Dateisuche verfügbar.

## Funktionen

- Verzeichnisbaum, Schnellzugriff/Favoriten, Tabs und gespeicherte Arbeitsbereiche.
- Zwei Dateiansichten zum Kopieren und Verschieben per Drag-and-drop.
- Ausschneiden/Kopieren/Einfügen, Konfliktentscheidungen für den Auftrag merken, Papierkorb.
- Rückgängigmachen von Kopier-/Verschiebeaufträgen während der laufenden Sitzung.
- Windows-nahe Tastenkürzel: Strg+C/X/V, F2, F5, Alt+Pfeile; zusätzlich Mac-Befehlstasten.
- Sortierbare Details, Liste und kompakte Ansicht; Dateinamensuche in Unterordnern.
- Vorschau mit Leertaste, automatische Aktualisierung beim Wechsel per Pfeiltaste.
- Fensterpositionen für Bildschirmhälften und den nutzbaren ganzen Bildschirm.
- Sicheres Auswerfen externer lokaler Laufwerke über macOS, ohne erzwungenes Trennen.
- Botti zeigt Gesamtfortschritt, Dateizähler, Geschwindigkeit und geschätzte Restzeit.
- Optionaler lokaler Datei-Chat mit Metadatensuche und Zusammenfassung ausgewählter Text-/PDF-Auszüge.

## Grenzen und Verhalten

Branch ist **keine vollständige Windows-Explorer-Nachbildung** und ersetzt Finder nicht systemweit.
Symbolraster/Miniaturen, Gruppierung, ein angedockter Vorschau-/Detailsbereich und ZIP-Verwaltung fehlen.

**Ordnerkonflikte:** „Ersetzen“ ersetzt den gesamten Zielordner; es führt Ordnerinhalte nicht zusammen.
Das alte Ziel landet im Papierkorb. Ohne Zusatztaste verschiebt Drag-and-drop innerhalb von Branch
auch über Laufwerke hinweg. Strg oder Option beim Ziehen kopiert.

Undo gilt nur für Übertragungen in der laufenden Sitzung. „Stoppen“ beendet einen Auftrag nach dem
aktuellen Objekt, bei einem Ordner also nach dessen Inhalt. Suche und KI-Auszüge sind begrenzt;
KI-Antworten können falsch sein. Netzwerkvolumes und Cloud-Platzhalter wurden nicht umfassend getestet.

Die App sendet selbst keine Dateien an einen KI-Server und speichert den Chat nicht dauerhaft.
Ein vom Benutzer aufgerufener macOS-Freigabedienst oder Cloud-Dateianbieter kann eigene Netzwerkzugriffe ausführen.

Details: [Anleitung](docs/Anleitung.txt) · [Explorer-Funktionsabgleich](docs/Explorer-Abgleich.txt)

## Aus dem Quellcode bauen

Benötigt werden ein Mac mit Apple Silicon, **Xcode 26 oder neuer** und das macOS-26-SDK.
Es werden keine Swift-Pakete oder sonstigen externen Bibliotheken heruntergeladen.

```sh
git clone https://github.com/maildienste-cell/branch-file-manager.git
cd branch-file-manager
./build.command
open build/Branch.app
```

Das Skript erzeugt die App vollständig aus `Source/` und `Resources/`, signiert sie lokal
und führt die Dateioperationstests aus. Die Tests erzeugen temporäre Testdateien;
ein Test prüft den echten macOS-Papierkorb und stellt seine eigenen Testdateien wieder her.

Zusätzliche Tests (nur in einer angemeldeten macOS-Grafiksitzung):

```sh
build/Branch.app/Contents/MacOS/Branch --ui-test /tmp/branch-ui.png
build/Branch.app/Contents/MacOS/Branch --ai-test
```

Der UI-Test verwendet isolierte App-Einstellungen, öffnet Testfenster und erzeugt einen Screenshot,
der Benutzernamen/Ordnernamen zeigen kann. Solche Screenshots nicht ungeprüft veröffentlichen.
Der KI-Test benötigt das verfügbare lokale Apple-Modell. Echte Laufwerke werden nicht ausgeworfen.

## Entwicklung und Rückmeldungen

Fehler bitte über [Issues](https://github.com/maildienste-cell/branch-file-manager/issues) melden,
mit macOS-Version, App-Version und reproduzierbaren Schritten. Keine privaten Dateiinhalte,
Zugangsdaten oder unbereinigten Screenshots anhängen.

Projekt, Symbol und Botti werden mitgeliefert. Windows/Microsoft und Apple/macOS sind Referenzen
für Bedienung bzw. Plattform; das Projekt ist mit diesen Unternehmen nicht verbunden.

## Lizenzstatus

Derzeit ist keine Open-Source-Lizenz vergeben. Die öffentliche Sichtbarkeit des
Repositories ist keine allgemeine Erlaubnis zur Weiterverwendung, Änderung oder
Weiterveröffentlichung des Codes. Eine Lizenzentscheidung kann später ergänzt werden.
