# DartVision – Redesign v2

Branch: `redesign-v2` (basiert auf `V1_Detection-on-Phone`, damit die CoreML-Modelle enthalten sind).

> **Wichtig:** Der Code wurde unter Windows geschrieben und konnte nicht kompiliert werden.
> Vor dem ersten Test auf dem Mac in Xcode 26 bauen und die Diagnose in der App ausführen
> (Einstellungen → Diagnose & Selbsttest). Alle Logik-Tests sollten grün sein.

## 1. Gefundene Fehler im bisherigen Code

### Spiellogik (`main`)
| # | Problem | Folge |
|---|---------|-------|
| 1 | Kein Bust im Kamera-Modus: `max(rest - wurf, 0)` | Überwerfen setzt den Rest auf 0 und erklärt den Spieler zum Sieger |
| 2 | `doubleOut` wird im Kamera-Modus nie geprüft | Finish mit Single zählt |
| 3 | Ein Zug endet nur bei genau 3 erkannten Darts | Daneben/abgeprallt → Zug hängt; Checkout mit 1–2 Darts unmöglich |
| 4 | Keine "Darts gezogen"-Erkennung | Steckende Darts werden dem nächsten Spieler gutgeschrieben |
| 5 | `NotificationCenter`-Observer bei jedem `onAppear` neu registriert | Nach Zurück aus "Analog" wird jede Aufnahme mehrfach abgezogen |
| 6 | Korrektur zieht den korrigierten Wert zusätzlich ab, pausiert die Kamera nicht | Doppelter Abzug, falscher Stand |
| 7 | `GameModeSelectionView` existiert doppelt (`RareFiles/`) | `main` baut mit synchronisierten Ordnern vermutlich nicht |
| 8 | Analog-Modus: Bust setzt frühere Darts des Zugs nicht zurück, Bull (50) zählt nicht als Doppel, T25 möglich, Rest 1 kein Bust | Falsche Stände |

### Erkennung
| # | Problem | Folge |
|---|---------|-------|
| 9 | 12-MP-JPEG mit Qualität 1.0 (3–6 MB) alle ~4 s + feste 3–4 s Wartezeiten | Hohe Latenz, viel Datenvolumen |
| 10 | Jedes Foto wird in die Fotomediathek gespeichert | Datenschutz, Speicher |
| 11 | On-Device: Bild wird auf 1216×1216 **gestreckt** statt letterboxed (Training/Ultralytics nutzt Letterbox) | Verzerrte Darts → schlechtere Erkennung |
| 12 | On-Device: NMS nur über Box-IoU 0,45 | Eng gruppierte Darts (T20) löschen sich gegenseitig |
| 13 | On-Device: Ausgabe-Tensor ohne Strides gelesen, Output-Name fest `var_1344` | Bricht bei anderem Export |
| 14 | Server rundet Board-Koordinaten auf ganze Pixel (≈ 0,85 mm) | Darts am Draht kippen (in den Referenzdaten: 4 ↔ 13) |
| 15 | Server-Inferenz mit `imgsz=800` auf dem ganzen Foto, `Darts.pt` wurde mit 928 trainiert | Board nur ~400 px groß → Doppelring ~9 px breit |
| 16 | Kalibrierpunkte aus einem einzigen Bild, nie gemittelt | Kalibrier-Rauschen wird zu systematischem Fehler aller Würfe |

### Sicherheit
- Im Repo lag ein **privater SSH-Schlüssel** (`DartVisionApp/key321`) – das Repo ist öffentlich.
  Auf diesem Branch ist er gelöscht, in der Git-Historie aber weiterhin sichtbar.
  → Schlüssel überall widerrufen (`authorized_keys`, GitHub) und neu erzeugen; Historie ggf. mit `git filter-repo` bereinigen.
- Der Server-Endpunkt `/upload` hat keine Authentifizierung.

## 2. Neue Architektur

```
DartVisionApp/
├─ Core/        reine Logik, ohne UI – im Selbsttest geprüft
│  ├─ Hit, BoardGeometry      Treffer, Board-Maße (mm), Scoring, Drahtabstand
│  ├─ Homography, BoardCalibration   Bild ↔ Board (normalisierte DLT), Plausibilitätsprüfung
│  ├─ X01Match                ereignisbasiertes Regelwerk (Bust, In/Out-Regeln, Legs, Undo, Korrektur, Statistik)
│  ├─ CheckoutCalculator      Finish-Wege für jeden Rest und jede Anzahl übriger Darts
│  ├─ ThrowTracker            Mehr-Frame-Tracking, Takeout-Erkennung
│  └─ SelfTest                in-App-Tests
├─ Detection/   KI: OnDeviceDetector (CoreML) und ServerDetector, gemeinsames Protokoll
├─ Camera/      Videostream (4K, 15 fps), Ausrichtung per RotationCoordinator, Zoom, Bewegungssensor
├─ Game/        GameSession (Ablauf), Einstellungen, Sprachausgabe, Trainingsdaten
└─ UI/          neues Design: Home, Kalibrierung, Spiel, Korrektur, Ergebnis, Einstellungen, Diagnose
```

## 3. Was die Erkennung jetzt genauer macht

1. **Letterbox statt Strecken** – Modell-Input entspricht dem Training.
2. **Kalibrierung über 5 Frames gemittelt** (Median + Ausreißerfilter), danach alle 20 s geprüft und sanft nachgeführt; bei Bewegung des Handys automatische Neukalibrierung.
3. **Kalibrierung prüfbar und justierbar** – Ringe werden aufs Standbild projiziert, die 4 Punkte lassen sich mit halber Fingergeschwindigkeit verschieben.
4. **Mehr-Frame-Bestätigung** – ein Dart zählt erst, wenn er in 2 Frames an derselben Stelle gesehen wurde; die Position ist der konfidenzgewichtete Mittelwert aller Beobachtungen.
5. **Enge Gruppen** – Duplikatfilter über den Abstand der Spitzen (~3 mm) statt Box-Überlappung; ein zweiter Dart 7 mm neben dem ersten wird als neuer Dart erkannt.
6. **Verdeckte Darts bleiben erhalten**, ältere Darts werden eingefroren, sobald ein neuer dazukommt.
7. **Takeout-Erkennung** – leeres Board über ≥ 1 s *und* Board sichtbar (Kalibrierpunkte erkannt) → Darts gezogen. Verdeckt jemand das Board, zählt das nicht. Fehlende Darts werden als Miss gewertet, der Zug hängt nie mehr.
8. **Unsicherheit sichtbar** – Darts < 1,5 mm am Draht oder mit niedriger Konfidenz werden orange markiert und lassen sich mit einem Tipp korrigieren.
9. **Wertung lokal und in Fließkomma** – identisch für beide Backends, keine Rundung auf Pixel.
10. **Trainingsdaten aus Korrekturen** (optional) – Bild + Kalibrierung + KI-Werte + korrigierte Werte landen in der Dateien-App. Genau diese Fehlerfälle bringen beim Nachtrainieren am meisten.
11. **Board-Zoom (experimentell)** – analysiert nur den Bereich ums Board mit höherer Auflösung. Standardmäßig aus; mit der Diagnose prüfen, ob es mit den aktuellen Modellen hilft.

## 4. Spielfunktionen

- 301 / 501 / 701, Single/Double/Master Out, Single/Double In, Best of 1/3/5/7 mit wechselndem Anwurf
- Bis zu 6 Spieler, Reihenfolge mischen
- Kamera- oder manuelle Zählung (Tastenfeld oder aufs Board tippen) – gleiches Regelwerk
- Undo über Zug- und Leg-Grenzen, Korrektur des aktuellen/letzten Zugs mit Live-Vorschau
- Checkout-Vorschläge passend zu den verbleibenden Darts
- Statistik: 3-Dart-Schnitt, höchste Aufnahme, 180er, 140+, 100+, höchstes Finish
- Caller-Ansagen (deutsch), Haptik, Spiel wird bei Abbruch gespeichert und kann fortgesetzt werden

## 5. Server (CptFrechdachsRpt) – konkrete Verbesserungen

Die App rechnet die Wertung jetzt selbst aus den Board-Koordinaten. Für mehr Genauigkeit im Server-Modus:

1. **Keine Rundung auf ganze Pixel** – in `V4_Extract_DartCenters.transform_dart_keypoints_absolute`
   `x_i, y_i = int(round(...))` ersetzen durch `float(pt_aligned[0]), float(pt_aligned[1])`.
2. **Inferenz-Auflösung = Trainings-Auflösung** – `Darts.pt` wurde mit `imgsz=928` trainiert, `Board.pt` mit 800,
   `run_yolo_on_image2` nutzt fest 800. Besser: `model.predict(..., imgsz=model.overrides.get("imgsz", 928))`
   (für das YOLO26-Modell den eigenen Trainingswert verwenden).
3. **Board-Ausschnitt statt Vollbild** – wenn Keypoints übergeben werden, das Bild auf den Board-Bereich
   (+ ~30 % Rand) zuschneiden und darauf die Darts suchen; Koordinaten danach zurückrechnen.
   Wirkt am stärksten, wenn das Modell ebenfalls auf solchen Ausschnitten trainiert wird.
4. **Keine Debug-Bilder pro Anfrage** (`warped_input.jpg`, `warped_withBoard1.jpg`, `Boardresults.txt`) – kostet Zeit.
5. **Versionen prüfen** – `requirements.txt` pinnt `ultralytics==8.3.23`, der Server lädt aber ein YOLO26-Modell
   (`Yolo26Darts_70.pt`, nicht im Repo); YOLO26 braucht eine neuere Ultralytics-Version.
6. **Endpunkt absichern** – z. B. einfacher API-Key-Header, damit nicht jeder Bilder hochladen kann.
7. **Lizenz** – Ultralytics/YOLO ist AGPL-3.0. Für eine geschlossene App im App Store braucht es entweder
   eine Ultralytics-Enterprise-Lizenz oder ein Modell mit permissiver Lizenz (siehe Recherche).

## 6. Recherche: bessere Modelle und Lösungen (Stand Okt. 2026)

| System | Aufbau | Genauigkeit |
|---|---|---|
| [DeepDarts](https://arxiv.org/abs/2105.09880) (Basis eurer 4 Kalibrierpunkte) | 1 Kamera | 94,7 % richtige Gesamtpunktzahl frontal, 84,0 % bei schrägen Winkeln (~16.000 Bilder) |
| [Dart Sense](https://github.com/bnww/dart-sense) | 1 Kamera, YOLOv8n | 88,4 % (nur nicht-kommerzielle Lizenz) |
| [Autodarts](https://autodarts.diy/) | 3 Kameras, 360°-LED-Ring | „bis zu 99 %“; laut Doku bringt mehr als 720p nichts |
| [Scolia](https://scoliadarts.com/compare/) | mehrere Kameras | ~99,5–99,8 % |
| [Autodarts Lens](https://winmau.com/pages/autodarts-x-lens), [DartsMind](https://apps.apple.com/us/app/id1018594473) | 1 Handy (direkte Konkurrenz) | keine Zahlen veröffentlicht |

Erkenntnisse:
- Mit **einer** Kamera liegen veröffentlichte Werte bei ~85–95 %. Die ~99 % kommerzieller Systeme kommen von **mehreren Kameras**. Hauptfehler bei einer Kamera: verdeckte Spitzen in engen Gruppen.
- **YOLO26-pose** (Ultralytics ≥ 8.4.0, seit Jan. 2026): auf COCO +7,2 mAP gegenüber YOLO11n-pose bei gleicher Größe, ohne NMS, CoreML-Export möglich. Für Darts gibt es keine Daten → selbst messen.
- **Lizenz:** Ultralytics (YOLO11/YOLO26) ist AGPL-3.0 → für eine geschlossene App im App Store braucht es die [Enterprise-Lizenz](https://www.ultralytics.com/license) oder ein permissives Modell. Plan B: [RF-DETR Keypoint](https://github.com/roboflow/rf-detr) (Apache-2.0, seit Juni 2026 als Preview, deutlich größer, CoreML für Keypoints ungeprüft) oder [RTMPose/RTMO](https://github.com/open-mmlab/mmpose) (Apache-2.0).
- Autodarts und Scolia erkennen den **Takeout** (Hand im Bild → Erkennung pausiert) und tragen Bounce-outs am Ende der Aufnahme als 0 ein – das entspricht der neuen Tracker-Logik in der App.

Empfehlung (nach Wirkung):
1. **Eigenes Testset + Kennzahl**: 200–500 Bilder aus der echten Montageposition (enge Gruppen, dunkle Darts), Anteil richtiger Aufnahmen messen. Ohne das lässt sich keine Modelländerung bewerten. Die Trainingsdaten-Funktion der App liefert genau die Fehlerfälle.
2. **Lizenzfrage klären** und dann **Darts-Modell neu trainieren**: YOLO26-pose (falls Enterprise-Lizenz/Open Source) oder RF-DETR Keypoint; Trainingsauflösung = Inferenzauflösung, Board-Ausschnitte mittrainieren (dann bringt der Board-Zoom echte Pixel pro mm).
3. **Setup-Hinweise**: leicht seitlich statt exakt frontal (Spitze sonst verdeckt), Ringlicht, kein Gegenlicht – in der Kalibrierung umgesetzt.
4. Später optional: **Zwei-Geräte-Modus** (zweites iPhone/iPad von der Seite) – der einzige Weg Richtung 99 %.

## 7. Nächste Schritte

1. In Xcode 26 bauen, Diagnose ausführen (Logik-Tests + Testbilder).
2. Am Board testen: Kalibrierung (px/mm-Hinweis beachten, ideal ≥ 3 px/mm), dann ein paar Legs.
3. Trainingsdaten sammeln aktivieren und nach einigen Spielen die Fehlerfälle labeln.
4. Modell nachtrainieren (siehe Recherche-Empfehlungen).
