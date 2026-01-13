/*
 Fehler:
    IN ContentView, macht bei Überworfen rest < 0 (DOUBLE UND NICHT DOUBLE) 2x das DartTracker.reset keinen Sinn da nicht mehr überprüft werden kann, ob ob bei einem nächsten Bild die gleichen Darts noch stecken (gleicher Spieler)
        LÖSUNG: Einfach rausnehmen. Der Spieler wurde bereits auf dennächsten gewechselt scores werden auch 0 gesetzt sobal bewiesen das neue Runde ist.   /erledigt
 
 
    IN Content View bei Winner muss is GameFinished genommen werden anstatt isGameactiveetc. in gameFinished muss wieder das schließen des Overlay deaktiviert werden.
        Ansonsten geht es auf und ploppt direkt wieder zu. bzw
        Same bei rest == !doubleout /erledigt
 
 
    FUNKTIONIERT das oder Zeichen bei in DartTracker von isBusted /erledigt: ja
 
 
    WENN ein spieler einen Dartwirft dieser wird zurückgegeben etc., dann nächste Runde wieder derselbe Pfeil. Wird ja wieder eine Liste von der länge 1 zurückgegeben. Dadurch wird throw gestartet. Die Scores werden nicht visuell geupdatet. Auf jeden Fall keine Ahnung was es bewirkt so richtig, muss auf jeden Fall in DartTracker überpüft werden, ob die Liste sich überhaupt verändert hat. Wenn nicht dann .sameRound
        LÖSUNG: in DartTracker einen einfach vergleich einführen ob liste sich verändert hat. Kann natürlich auch sein, das aus unerklärlichen gründen Die liste zurückgesetzt wurde. Also nicht nur länge vergleichen, sondern auch ob werte sich verändert haben.  / erledigt
 
 
    IN CameraModel, wird immer nur der letzte Dart weitergegeben zum score berechnen. Wenn jedoch 2 neue Pfeile in der Liste auftauchen, wird nur der 2. pfeil zur berechnung genutzt. (Es werden zuwar die richtigen scores angezeigt, aber intern falscher score gespeichert).
 
    
 what happens:
 
 
 IF Darts in Server Antwort:
    
    Open Dartliste, count length
 
    IF == Drei Darts in der Liste vorhanden
        
        Überprüfe ob in den neuen Darts noch alte Darts stecken
                (Das hier dient nur um zu checken ob bereits alle Pfeile gezogen worden sind)

 
        WENN min, ein alter Dart steckt, dann return Gleiche Runde.
            Jetzt gehts zurück in die Camera Model.swift
        
        -> CAMERAMODEL -> .sameRound:
                    NÄCHSTE Runde
 
        WENN NICHT alter Dart steckt
        history.removeAll()
                ignoredDarts.removeALL // Rauslassen erstmal
        
        Die Score Anzeige wird geleert
   
    ES SIND NOCH KEINE 3 DARTS in der Liste:
 
        WENN einer der Pfeile aus Server Antwort bereits in der Liste? ignorieren und nächster Pfeil
        WENN NICHT dart anhängen.
        Und ScoreBoardUpdaten
        Dann return der neuen Liste
 
    
    -> CAMERAMODEL ->:
        Untersuchen der zurückgegebenen LISTE
        
        LISTE = 1 Dart   (Frage: WAS PASSIERT WENN NOCHMAL NUR EIN DART ZURÜCKKOMMT):
                mittels Throw wird der eine Dart an weitergegeben
                -> CONTENTVIEW ->:
                    DER remaining Score des aktuellen Spielers wird abgerufen
                    Raff ich nicht:         lastTurn = TurnSnapshot(playerIndex: currentIndex, scoreThrown: currentDart.score, previousRest: currentRest)
                    neuen Rest berechnen mit currentRest- der neuen Dartliste
                    
                    IST der neue Rest < 0 ?
                        isBusted wird gleich 1 gesetzt
                        -> DARTRACKER->
                            isBusted == True
                                WENN STECKEN in den neuen Darts noch alte? Same round
                                
                                WENN NICHT
                                    Liste wird geleert
                                    SCORES auch geleert
 
                        Score wird nicht aktualisiert
                        nächster Spieler
                        -> die Liste wird zurückgesetzt (Aber das macht ja eigentlich kein Sinn,
                            da jetzt nicht mehr überprüft werden kann ob Pfeil bereits gesteckt hat.
 
                    
                    WENN newRest == 0 und doubleOut in den Einstellungen aktiviert
                        IST DER FIELDTYPE == double?
                            Scores auf 0 gesetzt.
                            isGameActive NEIN
                            stopCapture
                            GEWINNER Pop Up
                            
                            //Muss nicht noch dartTracker und Keypoints etc. == 0 gesetzt werden , hier wird isGameActive = false gesetzt und stopCapturing das steckt aber bereits in der Funktion finishGAME drin, auß0erdem auch sämtliche Resets etc.
                        WENN NICHT:
                            nächster Spieler.
                            auch hier ist dartTracker.reset
                            Scores werden wie immer in der dartracker angezeigt etc.
                            verbaut, das ist falsch
                
                    Wenn rest > 0
                        der WURF ist nicht mehr Busted. Also isBusted = false. Normalerweise ist 0 könnte aber auf true gesetzt worden sein durch den letzten spieler.
                             warum hier wieder dartTracker.reset()? macht kein sinn
                            kein spieler wechsel, da ja noch nicht 3 pfeile
            
                okay jetzt kommt eine liste von 3 zurück:
                    -> CAMERA MODEL:
                        (wenn 2 neue darts kommen, gibt er trotzdem nur den letzten dart an didfinishturn weiter, bisher noch nicht weiter gedacht, fällt mir jetzt aber erstmal auf.
                        ,   okay das ist ziemlich sicher ein fehler. sobald 2 neue darts auf ein mal kommen, werden zwar die richtigen darts angezeigt. im hintergrund der score aber falsch berechnet. Das liegt daran das der immer nur den letzten pfeil weitergibt. wenn aber 2 neu sind, wird nur der 3. aus der liste für den neuen score genommen. dies passiert für länge 2 und 3.
                            
                            Lösung: ERSTMAL warum zur hölle wird der score in einem anderen script berechnet.
                                ZUR neuen Score berechnung, müssen alle neuen pfeile genommen werden. Es muss also der score von den neuen pfeilen addiert werden und dann zurückgegeben werden und dieser dann mit thrown bzw handleturnfinished weitergegeben zur score berevhnung.
                                    Daher musst DartTracker ein mal die gesamte history zurückgegeben und auch gleichzeitig eine liste mit den neu angehängten darts. Dann zur überprüfung der darts die history länge und dann zum weitergeben nur die neuen darts. score wird weiterhin in thrown bzw handleturnfinished berechnet, jedoch nur mit der Liste von den neuen darts nicht mit gesamt history. Weiterhin braucht es double oder single des darts.
                                Auch funktioniert das alles mit dpuble etc nicht. da auch hier nur der leitzte der darts überprüft wird. falls 2 neue sind und der erste überwirft. und der 2. dann perfekt passt. wird weiterhin angezeigt das der spieler gewonnen hat. wobei eigentlich beim 1. dart rausgeflogen.
                
                            
                            
 
                    
 
                    
                        
                        
                            
                        

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 */
