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
- Für Qwen 3.5 · 4B werden Ollama und das separat heruntergeladene Modell benötigt.
  Apple Intelligence ist eine Alternative ab macOS 26 mit verfügbarem Systemmodell.
  Ohne KI bleibt die einfache lokale Dateisuche verfügbar.

## Funktionen

- Verzeichnisbaum, Schnellzugriff/Favoriten, Tabs und gespeicherte Arbeitsbereiche.
- Schreibtisch, Downloads, Dokumente und Papierkorb immer im Schnellzugriff; eigene Favoriten bleiben erhalten.
  Der Papierkorb-Eintrag öffnet den macOS-Papierkorb im Finder.
- Zwei Dateiansichten zum Kopieren und Verschieben per Drag-and-drop.
- Ausschneiden/Kopieren/Einfügen, Konfliktentscheidungen für den Auftrag merken, Papierkorb.
- Rückgängigmachen von Kopier-/Verschiebeaufträgen während der laufenden Sitzung.
- Windows-nahe Tastenkürzel: Strg+C/X/V, F2, F5, Alt+Pfeile; zusätzlich Mac-Befehlstasten.
- Sortierung nach Name, Änderungsdatum, Erstellungsdatum, Dateityp und Größe, jeweils auf- und absteigend.
- Details, Liste und kompakte Ansicht; Dateinamensuche in Unterordnern.
- Vorschau mit Leertaste, automatische Aktualisierung beim Wechsel per Pfeiltaste.
- Fensterpositionen für Bildschirmhälften und den nutzbaren ganzen Bildschirm.
- Sicheres Auswerfen externer lokaler Laufwerke über macOS, ohne erzwungenes Trennen.
- Botti zeigt Gesamtfortschritt, Dateizähler, Geschwindigkeit und geschätzte Restzeit.
- Botti direkt in der App: großes helles Eingabefeld, kurze Antworten und Ergebnisse in der Dateiansicht.
- Lokale KI mit Qwen 3.5 · 4B über Ollama oder Apple Intelligence; Fragen zu ausgewählten Text-/PDF-Auszügen.
- Gewünschte Trefferzahl direkt auswählen, z. B. die drei größten Dateien; ein markierter Ordner hat Vorrang.
- Deutsche Offline-Spracheingabe mit Mikrofonknopf; erkannten Text vor dem Senden prüfen.

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

Details: [Anleitung](docs/Anleitung.txt) · [Explorer-Funktionsabgleich (Stand 3.1)](docs/Explorer-Abgleich.txt)

## Botti einrichten

Botti mit einem Klick auf die Figur oder **⌘J** öffnen. Das Regler-Symbol zeigt
Modellauswahl und Einstellungen. Für Qwen zuerst [Ollama](https://ollama.com) installieren,
starten und das Modell herunterladen:

```sh
ollama pull qwen3.5:4b
```

Danach **Qwen 3.5 · 4B** in Botti auswählen. Die App verbindet sich ausschließlich mit
`127.0.0.1:11434`; Modellgewichte sind nicht im App-Download enthalten. Ollama und
Modell haben eigene Lizenzen. Die Grundeinstellung bleibt Apple Intelligence.

„Markiere die größten 3 Dateien hier im Ordner mit der Farbe blau“ wählt die
Treffer direkt in Branch aus. Blau ist die Auswahl, kein dauerhafter Farb-Tag.
Unterordner werden in Botti nur auf ausdrücklichen Wunsch durchsucht. Bei Ergebnissen
über mehrere Unterordner stellt **F5** die normale Ordneransicht wieder her.

Der Mikrofonknopf fragt beim ersten Einsatz nach Mikrofon- und Spracherkennungszugriff.
Deutsche lokale Spracherkennung muss auf dem Mac verfügbar sein. Es gibt keinen
Cloud-Ausweichdienst. Die Aufnahme endet spätestens nach 55 Sekunden; Senden bleibt
manuell. Eine echte Mikrofonaufnahme mit erteilten Berechtigungen wurde noch nicht getestet.

Keine semantische Volltextsuche über alle Dokumente, keine OCR und keine direkte
Word-/Excel-Inhaltsauswertung. Dokumentantworten nutzen maximal acht PDF-Seiten bzw.
8.000 Zeichen. Suchfilter und Einschränkungen stehen unter **Details**.

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
Der KI-Test nutzt standardmäßig das verfügbare lokale Apple-Modell. Mit
`--ai-test -ai.provider ollama` wird stattdessen Qwen geprüft.
`--ui-test /tmp/branch-ui.png --botti-check -ai.provider ollama -ApplePersistenceIgnoreState YES`
prüft die integrierte Auswahl anhand temporärer Beispieldateien. Echte Laufwerke werden nicht ausgeworfen.

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
