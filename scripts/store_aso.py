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
