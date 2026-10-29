# -*- coding: utf-8 -*-
"""App Store name / subtitle / keywords per locale (ASO, prepared 2026-10-27 for the version after 1.8.0).

Name = "My Sound Alarm" + the most-searched alarm word in that language. Subtitle says what it does.
Keywords exclude words already in the name or subtitle (Apple indexes those already).
store_l10n.py reads this file, so rerunning it keeps these values. Limits: 30 / 30 / 100."""

ASO = {
 "ja":     ("My Sound Alarm - 好きな曲で目覚まし", "動画や曲のサビをアラームに",
            "長い,フル,音楽,着信音,抽出,朝,時計,スヌーズ,カスタム,好きな音,mp3,寝坊,二度寝,起きれない,大音量,音割れしない,ループ"),
 "en-US":  ("My Sound Alarm: Music Alarm", "Song or video sound as alarm",
            "wake,custom,long,full,ringtone,extract,mp3,morning,clock,loud,snooze,oversleep,sleeper,chorus,loop"),
 "en-GB":  ("My Sound Alarm: Music Alarm", "Song or video sound as alarm",
            "audio,track,tune,favourite,soundtrack,recording,trim,import,wav,m4a,aac,bedside,timer,sleep,backup"),
 "fr-FR":  ("My Sound Alarm - Réveil", "Musique ou vidéo comme alarme",
            "sonnerie,chanson,audio,mp3,extraire,couper,matin,horloge,son,perso,répéter,refrain,fort,sommeil"),
 "de-DE":  ("My Sound Alarm - Musikwecker", "Refrain aus Song oder Video",
            "wecker,klingelton,musik,lied,audio,mp3,schneiden,morgen,uhr,ton,weckton,eigener,laut,verschlafen"),
 "es-ES":  ("My Sound Alarm - Despertador", "Canción o vídeo como alarma",
            "tono,música,audio,mp3,recortar,mañana,reloj,sonido,repetir,estribillo,fuerte,dormir,bucle"),
 "es-MX":  ("My Sound Alarm - Despertador", "Canción o video como alarma",
            "tono,música,audio,mp3,recortar,mañana,reloj,sonido,repetir,estribillo,fuerte,dormir,bucle"),
 "pt-BR":  ("My Sound Alarm - Despertador", "Música ou vídeo como alarme",
            "toque,canção,áudio,mp3,cortar,manhã,relógio,som,repetir,refrão,alto,sono,acordar"),
 "it":     ("My Sound Alarm - Sveglia", "Il ritornello di brani e video",
            "suoneria,musica,canzone,audio,mp3,tagliare,mattina,orologio,suono,ripetere,allarme,forte,sonno"),
 "nl-NL":  ("My Sound Alarm - Muziekwekker", "Refrein uit nummer of video",
            "wekker,beltoon,muziek,liedje,audio,mp3,knippen,ochtend,klok,geluid,herhalen,hard,verslapen"),
 "ko":     ("My Sound Alarm - 음악 알람", "노래·동영상 소리를 알람으로",
            "알람음,기상,오디오,mp3,자르기,아침,시계,벨소리,모닝콜,반복,후렴,늦잠,큰소리"),
 "zh-Hans":("My Sound Alarm - 音乐闹钟", "把歌曲或视频声音设为闹钟",
            "铃声,音频,剪辑,起床,早晨,时钟,自定义,mp3,循环,提取,副歌,赖床,大声"),
 "pl":     ("My Sound Alarm - Budzik", "Muzyka lub wideo jako alarm",
            "dzwonek,piosenka,audio,mp3,przyciąć,poranek,zegar,dźwięk,powtarzanie,refren,głośny,zaspanie"),
 "cs":     ("My Sound Alarm - Hudební budík", "Refrén z písničky nebo videa",
            "vyzvánění,hudba,audio,mp3,stříhat,ráno,hodiny,zvuk,opakování,tón,hlasitý,zaspat"),
 "ar-SA":  ("My Sound Alarm - منبه موسيقي", "أغنية أو صوت فيديو كمنبه",
            "نغمة,موسيقى,mp3,قص,صباح,ساعة,تكرار,استيقاظ,رنين,مقطع,عالي,نوم"),
}


# --- Description + promotional text (same facts in every language; 2026-10-29) ---
DESC = {}

DESC["ja"] = ("好きな曲のサビや動画の音で起きられる目覚ましアプリ。選んだ部分が、止めるまでくり返し鳴ります。マナーモードでも鳴ります。",
"""My Sound Alarm は、好きな曲のいちばん好きな部分や、動画の音で起きられる iPhone の目覚ましアプリです。アラームはこのアプリで設定し、選んだ部分が止めるまでくり返し鳴ります。

■ 主な機能

【好きな部分で目覚める】
動画や音声ファイルを開くと波形が表示されるので、範囲を選ぶだけ。サビだけを切り出しても、1曲まるごとでもかまいません。試聴しながら調整できます。最後まで鳴ったら、また最初から鳴ります。

【長さの制限なし】
iPhone の自作着信音は約40秒までですが、My Sound Alarm では動画から最長10分、長い音声ファイルもそのまま取り込めます。

【動画から音声だけを取り出す】
写真ライブラリやファイルアプリの動画から、音声だけを取り出せます。

【音声ファイルの取り込み】
MP3・AAC・WAV・M4A に対応。ファイルアプリや、ほかのアプリの共有ボタンから追加できます。

【マナーモードでも鳴る】
My Sound Alarm のアラームは、Apple が iOS 26 で用意した仕組み（AlarmKit）で登録します。iPhone 標準の時計アプリのアラームと同じようにロック画面に表示され、マナーモードや集中モードでも、このアプリを閉じていても鳴ります。

【今すぐ鳴らす】
選んだ音を、本番のアラームと同じ音量ですぐに鳴らして確かめられます。

【寝過ごし防止（PRO・先行公開中）】
設定した時間までにアラームを止めなかったら、同じ音を大きくしてもう一度鳴らします。先行公開中に使い始めた方は、正式版以降もそのまま使えます。

【繰り返しとスヌーズ】
曜日ごとの繰り返しに対応。スヌーズは「なし・1・2・5・9・10分」から選べます。

【音源が一目で分かる】
アラームごとに、動画の一場面や音声ファイルのアートワークを表示します。

【ナイトモード】
iPhone を枕元の時計にできます。暗い部屋でも読みやすい、落ち着いた表示です。

■ 対応形式
MP3 / AAC / WAV / M4A / 動画（MOV・MP4）からの音声

■ 注意事項
・iOS 26 以降が必要です（AlarmKit）
・長い音ほど容量を使います。10分の音でおよそ50MBです
・Apple Music や Spotify などの配信サービスの曲は取り込めません
""")

EN_PROMO = "An alarm clock app that wakes you up to the chorus of a song or the sound from a video. The part you choose plays on repeat until you stop it, even in Silent mode."
EN_BODY = """My Sound Alarm is an iPhone alarm clock app that wakes you up to your {fav} part of a song, or to the sound from a video. You set your alarms in this app, and the part you choose plays on repeat until you stop it.

KEY FEATURES

Wake Up to the Part You Love
Open a video or an audio file, look at the waveform, and select a range. Keep just the chorus or the whole song. You can listen while you adjust it. When it reaches the end, it starts again.

No Length Limit
Custom iPhone ringtones stop at about 40 seconds. My Sound Alarm takes up to 10 minutes from a video, and long audio files can be imported as they are.

Take the Audio From a Video
Choose a video from your photo library or the Files app and keep only the sound.

Import Audio Files
MP3, AAC, WAV and M4A all work. Add them from the Files app, or send them from another app with the Share button.

Rings in Silent Mode
My Sound Alarm schedules its alarms with AlarmKit, the alarm framework Apple added in iOS 26. They appear on the Lock Screen like alarms from the built-in Clock app and ring in Silent mode and when a Focus is on, even when My Sound Alarm is closed.

Ring Now
Hear the sound you chose right away, at the same volume as a real alarm.

Oversleep Guard (Pro, early access)
If you haven't stopped an alarm by the time you choose, it plays the same sound again, louder. If you start using it during early access, you keep it after the full release.

Repeat Days and Snooze
Choose the days for each alarm. Snooze can be off or 1, 2, 5, 9 or 10 minutes.

See Your Sounds
Each alarm shows a frame from your video or the artwork from your audio file.

Night Mode
Your iPhone becomes a bedside clock, with large, soft numbers you can read in a dark room.

SUPPORTED FORMATS
MP3 / AAC / WAV / M4A / Audio from video (MOV, MP4)

NOTES
- Requires iOS 26 or later (AlarmKit)
- Longer sounds use more storage. A 10-minute sound is about 50 MB.
- Songs from streaming services such as Apple Music or Spotify can't be imported.
"""
DESC["en-US"] = (EN_PROMO, EN_BODY.format(fav="favorite"))
DESC["en-GB"] = (EN_PROMO.replace("favorite", "favourite"), EN_BODY.format(fav="favourite"))

DESC["fr-FR"] = ("Une app de réveil qui te réveille avec le refrain d’une chanson ou le son d’une vidéo. Le passage choisi se répète jusqu’à ce que tu l’arrêtes, même en mode silencieux.",
"""My Sound Alarm est une app de réveil pour iPhone qui te réveille avec ton passage préféré d’une chanson ou le son d’une vidéo. Tu règles tes alarmes dans cette app, et le passage choisi se répète jusqu’à ce que tu l’arrêtes.

FONCTIONS

Réveille-toi sur ton passage préféré
Ouvre une vidéo ou un fichier audio, regarde la forme d’onde et sélectionne une plage. Garde juste le refrain ou la chanson entière. Tu peux écouter pendant que tu ajustes. Arrivé à la fin, il recommence.

Pas de limite de durée
Les sonneries personnalisées de l’iPhone s’arrêtent à environ 40 secondes. My Sound Alarm prend jusqu’à 10 minutes d’une vidéo, et les longs fichiers audio peuvent être importés tels quels.

Le son d’une vidéo
Choisis une vidéo de ta photothèque ou de l’app Fichiers et garde seulement le son.

Import de fichiers audio
MP3, AAC, WAV et M4A. Ajoute-les depuis l’app Fichiers, ou envoie-les depuis une autre app avec le bouton Partager.

Sonne en mode silencieux
My Sound Alarm programme ses alarmes avec AlarmKit, le système d’alarmes ajouté par Apple dans iOS 26. Elles s’affichent sur l’écran verrouillé comme celles de l’app Horloge intégrée et sonnent en mode silencieux et quand un mode de concentration est activé, même quand My Sound Alarm est fermée.

« Ring now »
Écoute tout de suite le son choisi, au même volume qu’une vraie alarme.

Anti-grasse matinée (Pro, accès anticipé)
Si tu n’as pas arrêté une alarme à l’heure choisie, elle rejoue le même son, plus fort. Si tu commences à l’utiliser pendant l’accès anticipé, tu la gardes après la sortie officielle.

Répétition et rappel d’alarme
Choisis les jours de chaque alarme. Le rappel d’alarme peut être désactivé ou réglé sur 1, 2, 5, 9 ou 10 minutes.

Tes sons en un coup d’œil
Chaque alarme affiche une image de ta vidéo ou l’illustration de ton fichier audio.

Mode nuit
Ton iPhone devient un réveil de chevet, avec de grands chiffres doux lisibles dans le noir.

FORMATS
MP3 / AAC / WAV / M4A / Son de vidéo (MOV, MP4)

À SAVOIR
- Nécessite iOS 26 ou version ultérieure (AlarmKit)
- Un son long prend plus de place. Un son de 10 minutes fait environ 50 Mo.
- Les morceaux des services de streaming comme Apple Music ou Spotify ne peuvent pas être importés.
""")

DESC["de-DE"] = ("Eine Wecker-App, die dich mit dem Refrain eines Songs oder dem Ton aus einem Video weckt. Der gewählte Teil wiederholt sich, bis du ihn ausschaltest – auch im Stummmodus.",
"""My Sound Alarm ist eine Wecker-App fürs iPhone, die dich mit deinem Lieblingsteil eines Songs oder dem Ton aus einem Video weckt. Du stellst deine Wecker in dieser App, und der gewählte Teil wiederholt sich, bis du ihn ausschaltest.

FUNKTIONEN

Wach auf mit deinem Lieblingsteil
Öffne ein Video oder eine Audiodatei, schau auf die Wellenform und wähl einen Bereich aus. Nimm nur den Refrain oder den ganzen Song. Du kannst beim Anpassen reinhören. Am Ende fängt er wieder von vorn an.

Keine Längenbegrenzung
Eigene iPhone-Klingeltöne enden nach etwa 40 Sekunden. My Sound Alarm übernimmt bis zu 10 Minuten aus einem Video, und lange Audiodateien lassen sich so importieren, wie sie sind.

Ton aus Videos
Wähl ein Video aus deiner Fotomediathek oder der Dateien-App und behalte nur den Ton.

Audiodateien importieren
MP3, AAC, WAV und M4A. Füge sie aus der Dateien-App hinzu oder schick sie aus einer anderen App über die Teilen-Taste.

Klingelt im Stummmodus
My Sound Alarm plant seine Wecker mit AlarmKit, dem Wecker-Framework, das Apple mit iOS 26 eingeführt hat. Sie erscheinen wie Wecker der integrierten Uhr-App auf dem Sperrbildschirm und klingeln im Stummmodus und wenn ein Fokus aktiv ist – auch wenn My Sound Alarm geschlossen ist.

„Ring now“
Hör den gewählten Ton sofort, in derselben Lautstärke wie ein echter Wecker.

Verschlafschutz (Pro, frühe Version)
Wenn du einen Wecker bis zur gewählten Zeit nicht ausgeschaltet hast, spielt er denselben Ton noch einmal lauter. Wenn du ihn in dieser Zeit zu nutzen beginnst, behältst du ihn auch nach der offiziellen Veröffentlichung.

Wiederholen und Schlummern
Wähl die Tage für jeden Wecker. Schlummern ist aus oder 1, 2, 5, 9 oder 10 Minuten.

Deine Töne auf einen Blick
Jeder Wecker zeigt ein Bild aus deinem Video oder das Cover deiner Audiodatei.

Nachtmodus
Dein iPhone wird zur Nachttischuhr, mit großen, sanften Ziffern, die du im Dunkeln lesen kannst.

FORMATE
MP3 / AAC / WAV / M4A / Ton aus Videos (MOV, MP4)

HINWEISE
- Erfordert iOS 26 oder neuer (AlarmKit)
- Längere Töne belegen mehr Speicher. Ein 10-minütiger Ton hat etwa 50 MB.
- Songs aus Streamingdiensten wie Apple Music oder Spotify lassen sich nicht importieren.
""")

ES_BODY = """My Sound Alarm es una app de despertador para iPhone que te despierta con tu parte favorita de una canción o el sonido de un {video}. Configuras tus alarmas en esta app, y la parte que elijas se repite hasta que la detengas.

FUNCIONES

Despierta con tu parte favorita
Abre un {video} o un archivo de audio, mira la forma de onda y selecciona un tramo. Quédate solo con el estribillo o con la canción entera. Puedes escucharlo mientras lo ajustas. Al llegar al final, vuelve a empezar.

Sin límite de duración
Los tonos personalizados del iPhone se cortan a los 40 segundos aproximadamente. My Sound Alarm admite hasta 10 minutos de un {video}, y los archivos de audio largos se pueden importar tal cual.

El sonido de un {video}
Elige un {video} de tu fototeca o de la app Archivos y quédate solo con el sonido.

Importa archivos de audio
MP3, AAC, WAV y M4A. Añádelos desde la app Archivos o envíalos desde otra app con el botón Compartir.

Suena en modo silencio
My Sound Alarm programa sus alarmas con AlarmKit, el sistema de alarmas que Apple añadió en iOS 26. Aparecen en la pantalla bloqueada como las de la app Reloj integrada y suenan en modo silencio y con un modo de concentración activado, incluso con My Sound Alarm cerrada.

«Ring now»
Escucha al momento el sonido que elegiste, con el mismo volumen que una alarma de verdad.

{guard} (Pro, acceso anticipado)
Si no has detenido una alarma a la hora que elijas, vuelve a sonar con el mismo sonido, más fuerte. Si empiezas a usarla durante el acceso anticipado, la conservas después del lanzamiento oficial.

Repetición y posponer
Elige los días de cada alarma. Posponer puede estar desactivado o en 1, 2, 5, 9 o 10 minutos.

Tus sonidos de un vistazo
Cada alarma muestra una imagen de tu {video} o la portada de tu archivo de audio.

Modo noche
Tu iPhone se convierte en un reloj de mesilla, con números grandes y suaves que puedes leer a oscuras.

FORMATOS
MP3 / AAC / WAV / M4A / Sonido de {video} (MOV, MP4)

NOTAS
- Requiere iOS 26 o posterior (AlarmKit)
- Los sonidos largos ocupan más espacio. Un sonido de 10 minutos ocupa unos 50 MB.
- Las canciones de servicios de streaming como Apple Music o Spotify no se pueden importar.
"""
DESC["es-ES"] = ("Una app de despertador que te despierta con el estribillo de una canción o el sonido de un vídeo. Lo que elijas se repite hasta que lo detengas, también en modo silencio.",
                 ES_BODY.format(video="vídeo", guard="Protección contra quedarse dormido"))
DESC["es-MX"] = ("Una app de despertador que te despierta con el estribillo de una canción o el sonido de un video. Lo que elijas se repite hasta que lo detengas, también en modo silencio.",
                 ES_BODY.format(video="video", guard="Protección para no quedarte dormido").replace("mesilla", "buró"))

DESC["pt-BR"] = ("Um app de despertador que acorda você com o refrão de uma música ou o som de um vídeo. O trecho escolhido repete até você desligar, mesmo no modo silencioso.",
"""O My Sound Alarm é um app de despertador para iPhone que acorda você com o seu trecho favorito de uma música ou o som de um vídeo. Você configura os alarmes neste app, e o trecho escolhido repete até você desligar.

RECURSOS

Acorde com o seu trecho favorito
Abra um vídeo ou arquivo de áudio, veja a forma de onda e selecione um intervalo. Use só o refrão ou a música inteira. Dá para ouvir enquanto ajusta. Quando chega ao fim, começa de novo.

Sem limite de duração
Os toques personalizados do iPhone param em cerca de 40 segundos. O My Sound Alarm aceita até 10 minutos de um vídeo, e arquivos de áudio longos podem ser importados como estão.

O som de um vídeo
Escolha um vídeo da fototeca ou do app Arquivos e fique só com o som.

Importar arquivos de áudio
MP3, AAC, WAV e M4A. Adicione pelo app Arquivos ou envie de outro app pelo botão Compartilhar.

Toca no modo silencioso
O My Sound Alarm agenda os alarmes com o AlarmKit, o sistema de alarmes que a Apple incluiu no iOS 26. Eles aparecem na Tela Bloqueada como os do app Relógio nativo e tocam no modo silencioso e com um Foco ativado, mesmo com o My Sound Alarm fechado.

“Ring now”
Ouça na hora o som escolhido, no mesmo volume de um alarme de verdade.

Proteção contra perder a hora (Pro, acesso antecipado)
Se você não desligar um alarme até o horário escolhido, ele toca o mesmo som de novo, mais alto. Se começar a usar durante o acesso antecipado, continua com ele depois do lançamento oficial.

Repetição e soneca
Escolha os dias de cada alarme. A soneca pode ficar desativada ou em 1, 2, 5, 9 ou 10 minutos.

Seus sons de relance
Cada alarme mostra uma imagem do seu vídeo ou a capa do seu arquivo de áudio.

Modo noturno
Seu iPhone vira um relógio de cabeceira, com números grandes e suaves para ler no escuro.

FORMATOS
MP3 / AAC / WAV / M4A / Som de vídeo (MOV, MP4)

OBSERVAÇÕES
- Requer iOS 26 ou posterior (AlarmKit)
- Sons mais longos ocupam mais espaço. Um som de 10 minutos tem cerca de 50 MB.
- Músicas de serviços de streaming como Apple Music ou Spotify não podem ser importadas.
""")

DESC["it"] = ("Un’app sveglia che ti sveglia con il ritornello di una canzone o con l’audio di un video. La parte che scegli si ripete finché non la fermi, anche in modalità silenziosa.",
"""My Sound Alarm è un’app sveglia per iPhone che ti sveglia con la tua parte preferita di una canzone o con l’audio di un video. Imposti le sveglie in questa app, e la parte che scegli si ripete finché non la fermi.

FUNZIONI

Svegliati con la tua parte preferita
Apri un video o un file audio, guarda la forma d’onda e seleziona un intervallo. Tieni solo il ritornello o la canzone intera. Puoi ascoltare mentre regoli. Quando arriva alla fine, ricomincia.

Nessun limite di durata
Le suonerie personalizzate dell’iPhone si fermano a circa 40 secondi. My Sound Alarm accetta fino a 10 minuti da un video, e i file audio lunghi si possono importare così come sono.

L’audio di un video
Scegli un video dalla libreria foto o dall’app File e tieni solo l’audio.

Importa file audio
MP3, AAC, WAV e M4A. Aggiungili dall’app File o inviali da un’altra app con il pulsante Condividi.

Suona in modalità silenziosa
My Sound Alarm programma le sue sveglie con AlarmKit, il sistema di sveglie introdotto da Apple in iOS 26. Compaiono sulla schermata di blocco come quelle dell’app Orologio integrata e suonano in modalità silenziosa e con una modalità Full Immersion attiva, anche con My Sound Alarm chiusa.

“Ring now”
Ascolta subito il suono scelto, allo stesso volume di una vera sveglia.

Anti-sonno (Pro, accesso anticipato)
Se non hai fermato una sveglia entro l’orario scelto, suona di nuovo con lo stesso suono, più forte. Se inizi a usarla durante l’accesso anticipato, la mantieni dopo il rilascio ufficiale.

Ripetizione e posticipa
Scegli i giorni di ogni sveglia. Posticipa può essere disattivato o di 1, 2, 5, 9 o 10 minuti.

I tuoi suoni a colpo d’occhio
Ogni sveglia mostra un’immagine del tuo video o la copertina del tuo file audio.

Modalità notte
Il tuo iPhone diventa un orologio da comodino, con numeri grandi e morbidi da leggere al buio.

FORMATI
MP3 / AAC / WAV / M4A / Audio da video (MOV, MP4)

NOTE
- Richiede iOS 26 o versioni successive (AlarmKit)
- I suoni lunghi occupano più spazio. Un suono di 10 minuti pesa circa 50 MB.
- I brani dei servizi di streaming come Apple Music o Spotify non si possono importare.
""")

DESC["nl-NL"] = ("Een wekker-app die je wekt met het refrein van een nummer of het geluid van een video. Het gekozen stuk herhaalt tot je het uitzet, ook in de stille modus.",
"""My Sound Alarm is een wekker-app voor iPhone die je wekt met je favoriete stuk van een nummer of het geluid van een video. Je stelt je wekkers in deze app in, en het gekozen stuk herhaalt tot je het uitzet.

FUNCTIES

Word wakker met je favoriete stuk
Open een video of audiobestand, bekijk de golfvorm en selecteer een bereik. Neem alleen het refrein of het hele nummer. Je kunt meeluisteren terwijl je het aanpast. Aan het eind begint het opnieuw.

Geen lengtelimiet
Eigen iPhone-beltonen stoppen na ongeveer 40 seconden. My Sound Alarm neemt tot 10 minuten uit een video, en lange audiobestanden kun je importeren zoals ze zijn.

Het geluid van een video
Kies een video uit je fotobibliotheek of de Bestanden-app en houd alleen het geluid over.

Audiobestanden importeren
MP3, AAC, WAV en M4A. Voeg ze toe vanuit de Bestanden-app of stuur ze vanuit een andere app met de deelknop.

Gaat af in de stille modus
My Sound Alarm plant zijn wekkers in met AlarmKit, het wekkersysteem dat Apple in iOS 26 heeft toegevoegd. Ze verschijnen op het toegangsscherm zoals wekkers van de ingebouwde Klok-app en gaan af in de stille modus en als een focus aan staat, ook als My Sound Alarm gesloten is.

‘Ring now’
Hoor het gekozen geluid meteen, op hetzelfde volume als een echte wekker.

Verslaapbeveiliging (Pro, vroege toegang)
Als je een wekker niet hebt uitgezet vóór de tijd die je kiest, speelt hij hetzelfde geluid nog een keer, harder. Als je hem tijdens de vroege toegang gaat gebruiken, houd je hem na de officiële release.

Herhalen en sluimeren
Kies de dagen voor elke wekker. Sluimeren kan uit staan of 1, 2, 5, 9 of 10 minuten zijn.

Je geluiden in één oogopslag
Elke wekker toont een beeld uit je video of de illustratie van je audiobestand.

Nachtmodus
Je iPhone wordt een nachtkastjesklok, met grote, zachte cijfers die je in het donker kunt lezen.

FORMATEN
MP3 / AAC / WAV / M4A / Geluid uit video (MOV, MP4)

OPMERKINGEN
- Vereist iOS 26 of nieuwer (AlarmKit)
- Langere geluiden nemen meer ruimte in. Een geluid van 10 minuten is ongeveer 50 MB.
- Nummers uit streamingdiensten zoals Apple Music of Spotify kunnen niet worden geïmporteerd.
""")

DESC["ko"] = ("좋아하는 노래의 후렴이나 동영상 소리로 깨워 주는 알람 앱. 고른 부분이 끌 때까지 반복해서 울리고, 무음 모드에서도 울립니다.",
"""My Sound Alarm은 좋아하는 노래의 원하는 부분이나 동영상 소리로 깨워 주는 iPhone 알람 앱입니다. 알람은 이 앱에서 설정하고, 고른 부분이 끌 때까지 반복해서 울립니다.

■ 주요 기능

[좋아하는 부분으로 일어나기]
동영상이나 오디오 파일을 열면 파형이 나타나니 구간을 고르기만 하면 됩니다. 후렴만 잘라도, 한 곡을 통째로 써도 됩니다. 들으면서 조절할 수 있습니다. 끝까지 울리면 처음부터 다시 울립니다.

[길이 제한 없음]
직접 만든 iPhone 벨소리는 약 40초까지지만, My Sound Alarm은 동영상에서 최대 10분, 긴 오디오 파일도 그대로 가져올 수 있습니다.

[동영상에서 소리만 꺼내기]
사진 보관함이나 파일 앱의 동영상에서 소리만 꺼낼 수 있습니다.

[오디오 파일 가져오기]
MP3, AAC, WAV, M4A를 지원합니다. 파일 앱이나 다른 앱의 공유 버튼으로 추가할 수 있습니다.

[무음 모드에서도 울림]
My Sound Alarm의 알람은 Apple이 iOS 26에 추가한 AlarmKit으로 등록됩니다. iPhone 기본 시계 앱의 알람처럼 잠금 화면에 표시되고, 무음 모드나 집중 모드가 켜져 있어도, 이 앱을 닫아도 울립니다.

["Ring now"]
고른 소리를 실제 알람과 같은 음량으로 바로 들어볼 수 있습니다.

[늦잠 방지 (Pro, 사전 공개)]
설정한 시간까지 알람을 끄지 않으면 같은 소리를 더 크게 다시 울립니다. 사전 공개 기간에 쓰기 시작한 분은 정식 출시 후에도 그대로 쓸 수 있습니다.

[반복과 다시 알림]
요일별 반복을 지원합니다. 다시 알림은 끔 또는 1·2·5·9·10분 중에서 고를 수 있습니다.

[소리를 한눈에]
알람마다 동영상의 한 장면이나 오디오 파일의 아트워크를 보여 줍니다.

[나이트 모드]
iPhone을 머리맡 시계로 쓸 수 있습니다. 어두운 방에서도 읽기 쉬운 차분한 화면입니다.

■ 지원 형식
MP3 / AAC / WAV / M4A / 동영상(MOV, MP4)의 소리

■ 참고
· iOS 26 이상이 필요합니다(AlarmKit)
· 긴 소리일수록 용량을 더 씁니다. 10분짜리 소리는 약 50MB입니다
· Apple Music, Spotify 같은 스트리밍 서비스의 노래는 가져올 수 없습니다
""")

DESC["zh-Hans"] = ("用歌曲副歌或视频声音叫醒你的闹钟 App。选好的片段会一直循环，直到你停止；静音模式下也会响。",
"""My Sound Alarm 是一款 iPhone 闹钟 App，可以用你最爱的歌曲片段或视频里的声音叫醒你。闹钟在这个 App 里设定，选好的片段会一直循环，直到你停止。

■ 主要功能

【用最爱的片段醒来】
打开视频或音频文件，看着波形选一段就行。可以只留副歌，也可以用整首歌。可以边听边调整。播到结尾会从头再来。

【没有长度限制】
iPhone 的自制铃声最长约 40 秒，而 My Sound Alarm 可以从视频中截取最长 10 分钟，较长的音频文件也能直接导入。

【只取视频里的声音】
从照片图库或“文件”App 中选一个视频，只保留声音。

【导入音频文件】
支持 MP3、AAC、WAV、M4A。可从“文件”App 添加，也可以在其他 App 中用“共享”按钮发送过来。

【静音模式下也会响】
My Sound Alarm 的闹钟通过 Apple 在 iOS 26 中加入的 AlarmKit 设定。它会像 iPhone 自带“时钟”App 的闹钟一样显示在锁定屏幕上，静音模式下、专注模式打开时，甚至关闭 My Sound Alarm 后也会响。

【“Ring now”】
用和真正闹钟相同的音量，马上试听你选的声音。

【防睡过头（Pro，抢先体验）】
如果到你设定的时间还没有停止闹钟，它会把同一个声音调大后再响一次。在抢先体验期间开始使用的用户，正式发布后也可以继续使用。

【重复与稍后提醒】
可按星期设定重复。稍后提醒可关闭，或设为 1、2、5、9、10 分钟。

【一眼认出你的声音】
每个闹钟会显示视频中的画面或音频文件的封面。

【夜间模式】
把 iPhone 变成床头时钟，大而柔和的数字在暗处也易于阅读。

■ 支持格式
MP3 / AAC / WAV / M4A / 视频（MOV、MP4）中的声音

■ 注意事项
· 需要 iOS 26 或更高版本（AlarmKit）
· 声音越长，占用空间越多。10 分钟的声音约 50 MB
· 无法导入 Apple Music、Spotify 等流媒体服务的歌曲
""")

DESC["pl"] = ("Aplikacja-budzik, która budzi cię refrenem piosenki albo dźwiękiem z wideo. Wybrany fragment powtarza się, dopóki go nie wyłączysz – także w trybie cichym.",
"""My Sound Alarm to aplikacja-budzik na iPhone’a, która budzi cię ulubionym fragmentem piosenki albo dźwiękiem z wideo. Budziki ustawiasz w tej aplikacji, a wybrany fragment powtarza się, dopóki go nie wyłączysz.

FUNKCJE

Budź się przy ulubionym fragmencie
Otwórz wideo lub plik audio, spójrz na wykres fali i zaznacz zakres. Zostaw sam refren albo całą piosenkę. Możesz słuchać podczas dopasowywania. Gdy dojdzie do końca, zaczyna od nowa.

Bez limitu długości
Własne dzwonki w iPhonie kończą się po około 40 sekundach. My Sound Alarm przyjmuje do 10 minut z wideo, a długie pliki audio można zaimportować w całości.

Dźwięk z wideo
Wybierz wideo z biblioteki zdjęć lub z aplikacji Pliki i zostaw sam dźwięk.

Import plików audio
MP3, AAC, WAV i M4A. Dodaj je z aplikacji Pliki albo wyślij z innej aplikacji przyciskiem Udostępnij.

Dzwoni w trybie cichym
My Sound Alarm planuje swoje budziki przez AlarmKit, system budzików dodany przez Apple w iOS 26. Pojawiają się na ekranie blokady jak budziki z wbudowanej aplikacji Zegar i dzwonią w trybie cichym i przy włączonym trybie skupienia, nawet gdy My Sound Alarm jest zamknięta.

„Ring now”
Posłuchaj wybranego dźwięku od razu, z tą samą głośnością co prawdziwy budzik.

Ochrona przed zaspaniem (Pro, wczesny dostęp)
Jeśli nie wyłączysz budzika do wybranej godziny, odtworzy ten sam dźwięk ponownie, głośniej. Jeśli zaczniesz z niej korzystać we wczesnym dostępie, zachowasz ją po oficjalnym wydaniu.

Powtarzanie i drzemka
Wybierz dni dla każdego budzika. Drzemka może być wyłączona albo trwać 1, 2, 5, 9 lub 10 minut.

Twoje dźwięki na pierwszy rzut oka
Każdy budzik pokazuje kadr z wideo albo okładkę pliku audio.

Tryb nocny
Twój iPhone staje się zegarem przy łóżku, z dużymi, łagodnymi cyframi czytelnymi w ciemności.

FORMATY
MP3 / AAC / WAV / M4A / Dźwięk z wideo (MOV, MP4)

UWAGI
- Wymaga iOS 26 lub nowszego (AlarmKit)
- Dłuższe dźwięki zajmują więcej miejsca. Dźwięk 10-minutowy to około 50 MB.
- Utworów z serwisów streamingowych, takich jak Apple Music czy Spotify, nie da się zaimportować.
""")

DESC["cs"] = ("Aplikace budíku, která tě probudí refrénem písničky nebo zvukem z videa. Vybraná část se opakuje, dokud ji nevypneš – i v tichém režimu.",
"""My Sound Alarm je aplikace budíku pro iPhone, která tě probudí oblíbenou částí písničky nebo zvukem z videa. Budíky nastavuješ v této aplikaci a vybraná část se opakuje, dokud ji nevypneš.

FUNKCE

Probuď se u oblíbené části
Otevři video nebo zvukový soubor, podívej se na průběh zvuku a vyber úsek. Nech si jen refrén, nebo celou písničku. Při úpravách můžeš poslouchat. Když dohraje do konce, začne znovu.

Bez omezení délky
Vlastní vyzváněcí tóny v iPhonu končí asi po 40 sekundách. My Sound Alarm vezme z videa až 10 minut a dlouhé zvukové soubory se dají importovat celé.

Zvuk z videa
Vyber video z knihovny fotek nebo z aplikace Soubory a nech si jen zvuk.

Import zvukových souborů
MP3, AAC, WAV a M4A. Přidej je z aplikace Soubory, nebo je pošli z jiné aplikace tlačítkem Sdílet.

Zvoní v tichém režimu
My Sound Alarm plánuje své budíky přes AlarmKit, systém budíků, který Apple přidal v iOS 26. Zobrazují se na zamčené obrazovce jako budíky z vestavěné aplikace Hodiny a zvoní v tichém režimu i při zapnutém režimu soustředění, i když je My Sound Alarm zavřená.

„Ring now“
Poslechni si vybraný zvuk hned, ve stejné hlasitosti jako skutečný budík.

Ochrana proti zaspání (Pro, předběžný přístup)
Pokud budík do zvolené doby nevypneš, přehraje stejný zvuk znovu a hlasitěji. Pokud ji začneš používat během předběžného přístupu, zůstane ti i po oficiálním vydání.

Opakování a odložení
Vyber dny pro každý budík. Odložení může být vypnuté, nebo 1, 2, 5, 9 či 10 minut.

Tvoje zvuky na první pohled
Každý budík ukazuje záběr z videa nebo obal zvukového souboru.

Noční režim
Z iPhonu se stanou hodiny u postele, s velkými jemnými číslicemi čitelnými ve tmě.

FORMÁTY
MP3 / AAC / WAV / M4A / Zvuk z videa (MOV, MP4)

POZNÁMKY
- Vyžaduje iOS 26 nebo novější (AlarmKit)
- Delší zvuky zabírají víc místa. 10minutový zvuk má asi 50 MB.
- Skladby ze streamovacích služeb, jako je Apple Music nebo Spotify, se nedají importovat.
""")

DESC["ar-SA"] = ("تطبيق منبه يوقظك على لازمة أغنية أو صوت من فيديو. يتكرر الجزء الذي تختاره حتى توقفه، حتى في الوضع الصامت.",
"""My Sound Alarm تطبيق منبه لجهاز iPhone يوقظك على جزئك المفضل من أغنية أو على الصوت من فيديو. تضبط منبهاتك في هذا التطبيق، ويتكرر الجزء الذي تختاره حتى توقفه.

الميزات

استيقظ على جزئك المفضل
افتح فيديو أو ملفًا صوتيًا، وانظر إلى الموجة الصوتية، وحدد نطاقًا. احتفظ باللازمة فقط أو بالأغنية كاملة. يمكنك الاستماع أثناء الضبط. وعندما يصل إلى النهاية يبدأ من جديد.

بلا حد للمدة
تتوقف نغمات iPhone المخصصة عند نحو 40 ثانية. يقبل My Sound Alarm حتى 10 دقائق من الفيديو، ويمكن استيراد الملفات الصوتية الطويلة كما هي.

الصوت من فيديو
اختر فيديو من مكتبة الصور أو تطبيق الملفات واحتفظ بالصوت فقط.

استيراد الملفات الصوتية
يدعم MP3 وAAC وWAV وM4A. أضفها من تطبيق الملفات أو أرسلها من تطبيق آخر بزر المشاركة.

يرن في الوضع الصامت
يجدول My Sound Alarm منبهاته باستخدام AlarmKit، وهو نظام المنبهات الذي أضافته Apple في iOS 26. تظهر على شاشة القفل مثل منبهات تطبيق الساعة المدمج، وترن في الوضع الصامت وعند تشغيل وضع التركيز، حتى عندما يكون My Sound Alarm مغلقًا.

«Ring now»
استمع فورًا إلى الصوت الذي اخترته، بمستوى صوت المنبه الحقيقي نفسه.

الحماية من النوم الزائد (Pro، وصول مبكر)
إذا لم توقف المنبه بحلول الوقت الذي تختاره، فسيعيد تشغيل الصوت نفسه بصوت أعلى. إذا بدأت استخدامها خلال الوصول المبكر، تحتفظ بها بعد الإصدار الرسمي.

التكرار والغفوة
اختر أيام كل منبه. يمكن إيقاف الغفوة أو ضبطها على 1 أو 2 أو 5 أو 9 أو 10 دقائق.

أصواتك في لمحة
يعرض كل منبه لقطة من الفيديو أو صورة غلاف الملف الصوتي.

الوضع الليلي
يصبح iPhone ساعة بجانب السرير، بأرقام كبيرة وهادئة يسهل قراءتها في الظلام.

الصيغ المدعومة
MP3 / AAC / WAV / M4A / الصوت من الفيديو (MOV وMP4)

ملاحظات
- يتطلب iOS 26 أو أحدث (AlarmKit)
- الأصوات الأطول تشغل مساحة أكبر. الصوت بطول 10 دقائق يبلغ نحو 50 ميغابايت.
- لا يمكن استيراد أغاني خدمات البث مثل Apple Music وSpotify.
""")
