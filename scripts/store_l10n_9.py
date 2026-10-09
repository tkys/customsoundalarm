# -*- coding: utf-8 -*-
"""Generate App Store metadata for 9 additional locales (fastlane/metadata/<locale>/).

Source of truth: fastlane/metadata/en-US. Re-run to regenerate; it overwrites
name / subtitle / keywords / promotional_text / description / URLs only.
Release notes are written per version, not here.
"""
import os
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..", "fastlane", "metadata")

L = {}

L["fr-FR"] = dict(
    subtitle="Se réveiller sur son refrain",
    keywords="réveil,sonnerie,musique,chanson,vidéo,audio,mp3,extraire,couper,matin,horloge,son,perso,répéter",
    promo="Réveille-toi avec la musique que tu aimes. Garde seulement le refrain d'une vidéo ou d'un fichier audio : il se répète jusqu'à ce que tu te lèves.",
    description="""Réveille-toi avec la musique que tu aimes. Garde seulement le passage que tu veux : le refrain, l'accroche, la phrase que tu chantes.

FONCTIONS PRINCIPALES

Réveille-toi sur ton passage préféré
On ne veut pas toute la chanson, juste un moment. Ouvre une vidéo ou un fichier audio, regarde la forme d'onde et fais glisser pour choisir le passage. Tu peux l'écouter pendant que tu ajustes. La forme d'onde montre où le son est fort et où il est calme.

Un passage court fonctionne bien. L'alarme le joue jusqu'au bout, puis recommence, jusqu'à ce que tu te lèves. Vingt ou trente secondes de refrain suffisent souvent.

Tes propres fichiers
L'app utilise l'audio que tu as déjà : un fichier de musique, un enregistrement de voix, le son d'une vidéo enregistrée. Aucun abonnement. Aucun catalogue à parcourir.

Le son d'une vidéo
Choisis une vidéo dans ta pellicule et garde uniquement le son. Idéal pour les vidéos enregistrées ou que tu as filmées toi-même.

Importer des fichiers audio
MP3, AAC, WAV et M4A sont pris en charge. Ouvre-les depuis l'app Fichiers.

Le système d'alarme d'Apple
L'app utilise AlarmKit, le système d'alarme d'Apple. Ton alarme sonne comme celle de l'app Horloge. Ce n'est pas une astuce en arrière-plan qui peut échouer au mauvais moment.

Repère tes sons
Chaque alarme affiche une image de son son : une image de ta vidéo ou la pochette de ton fichier. Tu distingues facilement tes alarmes.

Pas de limite de 40 secondes
Une sonnerie d'iPhone dure environ 40 secondes au maximum. Ici, tu peux prendre jusqu'à 10 minutes d'une vidéo, et les fichiers audio n'ont aucune limite de durée.

Feuille de partage
Envoie de l'audio ou de la vidéo vers l'app depuis d'autres apps.

Jours de répétition
Choisis les jours de chaque alarme : en semaine, le week-end ou les jours que tu veux.

Rappel d'alarme
Choisis 1, 2, 5 ou 10 minutes d'un geste, ou n'importe quelle autre durée.

Mode nuit
Ton iPhone devient un réveil de chevet. Les chiffres sont grands et doux, lisibles dans une pièce sombre.

FORMATS PRIS EN CHARGE
MP3 / AAC / WAV / M4A / Audio de vidéo (MOV, MP4)

REMARQUES
- Nécessite iOS 26 ou version ultérieure (AlarmKit)
- Un son long occupe plus d'espace. Un son d'alarme de 10 minutes fait environ 50 Mo.
""",
)

L["de-DE"] = dict(
    subtitle="Wach werden mit deinem Refrain",
    keywords="wecker,klingelton,musik,lied,song,video,audio,mp3,schneiden,morgen,uhr,ton,weckton,eigener",
    promo="Wach auf mit der Musik, die du liebst. Schneide nur den Refrain aus einem Video oder einer Audiodatei – er wiederholt sich, bis du aufstehst.",
    description="""Wach auf mit der Musik, die du liebst. Behalte nur den Teil, den du willst: den Refrain, die Hook, die Zeile, die du mitsingst.

FUNKTIONEN

Wach auf mit deinem Lieblingsteil
Die meisten wollen nicht den ganzen Song, sondern nur einen Teil davon. Öffne ein Video oder eine Audiodatei, sieh dir die Wellenform an und ziehe, um den Abschnitt auszuwählen. Du kannst ihn beim Anpassen anhören. Die Wellenform zeigt, wo es laut und wo es leise ist.

Ein kurzer Abschnitt funktioniert gut. Der Wecker spielt ihn bis zum Ende und dann wieder von vorn, bis du aufstehst. Zwanzig oder dreißig Sekunden Refrain reichen oft.

Deine eigenen Dateien
Die App nutzt Audio, das du schon hast: eine Musikdatei, eine Sprachaufnahme, den Ton aus einem gespeicherten Video. Kein Abo. Kein Musikkatalog zum Durchsuchen.

Ton aus einem Video
Wähle ein Video aus deiner Mediathek und behalte nur den Ton. Ideal für gespeicherte oder selbst gefilmte Videos.

Audiodateien importieren
MP3, AAC, WAV und M4A werden unterstützt. Öffne sie aus der Dateien-App.

Apples Wecker-System
Die App nutzt AlarmKit, das Wecker-System von Apple. Dein Wecker klingelt wie der in der Uhr-App. Kein Hintergrund-Trick, der im falschen Moment versagt.

Deine Töne auf einen Blick
Jeder Wecker zeigt ein Bild seines Tons: ein Bild aus deinem Video oder das Cover deiner Datei. So unterscheidest du deine Wecker leicht.

Keine 40-Sekunden-Grenze
Ein iPhone-Klingelton darf nur etwa 40 Sekunden lang sein. Hier kannst du bis zu 10 Minuten aus einem Video nehmen, und Audiodateien haben gar keine Längenbegrenzung.

Teilen-Menü
Sende Audio oder Video aus anderen Apps an diese App.

Wiederholung
Wähle die Tage für jeden Wecker: werktags, am Wochenende oder an beliebigen Tagen.

Schlummern
Wähle 1, 2, 5 oder 10 Minuten mit einem Tippen oder jeden anderen Wert.

Nachtmodus
Dein iPhone wird zur Uhr am Bett. Große, sanfte Ziffern, gut lesbar im dunklen Zimmer.

FORMATE
MP3 / AAC / WAV / M4A / Ton aus Video (MOV, MP4)

HINWEISE
- Benötigt iOS 26 oder neuer (AlarmKit)
- Längere Töne brauchen mehr Speicher. Ein 10-Minuten-Weckton belegt etwa 50 MB.
""",
)

_ES_DESC = """Despierta con la música que te gusta. Quédate solo con la parte que quieres: el estribillo, el gancho, la frase que cantas.

FUNCIONES PRINCIPALES

Despierta con tu parte favorita
Casi nadie quiere la canción entera, solo una parte. Abre un vídeo o un archivo de audio, mira la forma de onda y arrastra para elegir el fragmento. Puedes escucharlo mientras lo ajustas. La forma de onda te muestra dónde suena fuerte y dónde suave.

Un fragmento corto funciona bien. La alarma lo reproduce hasta el final y vuelve a empezar, hasta que te levantas. Veinte o treinta segundos del estribillo suelen bastar.

Tus propios archivos
La app usa el audio que ya tienes: un archivo de música, una grabación de voz, el sonido de un vídeo guardado. Sin suscripción. Sin catálogo que buscar.

El sonido de un vídeo
Elige un vídeo del carrete y quédate solo con el sonido. Ideal para vídeos guardados o grabados por ti.

Importar archivos de audio
Compatible con MP3, AAC, WAV y M4A. Ábrelos desde la app Archivos.

El sistema de alarmas de Apple
La app usa AlarmKit, el sistema de alarmas de Apple. Tu alarma suena igual que la de la app Reloj. No es un truco en segundo plano que puede fallar justo cuando lo necesitas.

Reconoce tus sonidos
Cada alarma muestra una imagen de su sonido: un fotograma de tu vídeo o la portada de tu archivo. Así distingues tus alarmas fácilmente.

Sin límite de 40 segundos
Un tono de iPhone solo puede durar unos 40 segundos. Aquí puedes tomar hasta 10 minutos de un vídeo, y los archivos de audio no tienen límite de duración.

Hoja para compartir
Envía audio o vídeo a esta app desde otras apps.

Días de repetición
Elige los días de cada alarma: entre semana, el fin de semana o los días que quieras.

Posponer
Elige 1, 2, 5 o 10 minutos con un toque, o el valor que prefieras.

Modo noche
Tu iPhone se convierte en un reloj de mesita. Números grandes y suaves, fáciles de leer a oscuras.

FORMATOS COMPATIBLES
MP3 / AAC / WAV / M4A / Audio de vídeo (MOV, MP4)

NOTAS
- Requiere iOS 26 o posterior (AlarmKit)
- Un sonido más largo ocupa más espacio. Un sonido de alarma de 10 minutos ocupa unos 50 MB.
"""

L["es-ES"] = dict(
    subtitle="Despierta con tu estribillo",
    keywords="despertador,alarma,tono,música,canción,vídeo,audio,mp3,recortar,mañana,reloj,sonido,repetir",
    promo="Despierta con la música que te gusta. Recorta solo el estribillo de un vídeo o un archivo de audio y sonará en bucle hasta que te levantes.",
    description=_ES_DESC,
)

L["es-MX"] = dict(
    subtitle="Despierta con tu coro favorito",
    keywords="despertador,alarma,tono,música,canción,video,audio,mp3,recortar,mañana,reloj,sonido,repetir",
    promo="Despierta con la música que te gusta. Recorta solo el coro de un video o un archivo de audio y sonará en bucle hasta que te levantes.",
    description=_ES_DESC.replace("vídeo", "video").replace("Vídeo", "Video")
        .replace("el estribillo, el gancho", "el coro, el gancho")
        .replace("segundos del estribillo", "segundos del coro")
        .replace("del carrete", "de tu galería")
        .replace("mesita", "buró"),
)

L["pt-BR"] = dict(
    subtitle="Acorde com seu refrão favorito",
    keywords="despertador,alarme,toque,música,canção,vídeo,áudio,mp3,cortar,manhã,relógio,som,repetir",
    promo="Acorde com a música que você ama. Corte só o refrão de um vídeo ou arquivo de áudio, e ele toca em repetição até você levantar.",
    description="""Acorde com a música que você ama. Fique só com a parte que você quer: o refrão, o gancho, o verso que você canta junto.

RECURSOS PRINCIPAIS

Acorde com sua parte favorita
Quase ninguém quer a música inteira, só um trecho. Abra um vídeo ou um arquivo de áudio, veja a forma de onda e arraste para escolher o trecho. Você pode ouvir enquanto ajusta. A forma de onda mostra onde o som é alto e onde é baixo.

Um trecho curto funciona bem. O alarme toca até o fim e começa de novo, até você levantar. Vinte ou trinta segundos do refrão costumam bastar.

Seus próprios arquivos
O app usa o áudio que você já tem: um arquivo de música, uma gravação de voz, o som de um vídeo salvo. Sem assinatura. Sem catálogo para procurar.

O som de um vídeo
Escolha um vídeo do rolo da câmera e fique só com o som. Ótimo para vídeos salvos ou gravados por você.

Importar arquivos de áudio
Compatível com MP3, AAC, WAV e M4A. Abra pelo app Arquivos.

O sistema de alarmes da Apple
O app usa o AlarmKit, o sistema de alarmes da Apple. Seu alarme toca do mesmo jeito que o do app Relógio. Não é um truque em segundo plano que pode falhar na hora errada.

Reconheça seus sons
Cada alarme mostra uma imagem do seu som: um quadro do vídeo ou a capa do arquivo. Fica fácil diferenciar seus alarmes.

Sem limite de 40 segundos
Um toque de iPhone só pode ter cerca de 40 segundos. Aqui você pode usar até 10 minutos de um vídeo, e arquivos de áudio não têm limite de duração.

Compartilhar
Envie áudio ou vídeo de outros apps para este app.

Dias de repetição
Escolha os dias de cada alarme: dias úteis, fins de semana ou os dias que quiser.

Soneca
Escolha 1, 2, 5 ou 10 minutos com um toque, ou qualquer outro valor.

Modo noturno
Seu iPhone vira um relógio de cabeceira. Números grandes e suaves, fáceis de ler no escuro.

FORMATOS COMPATÍVEIS
MP3 / AAC / WAV / M4A / Áudio de vídeo (MOV, MP4)

OBSERVAÇÕES
- Requer iOS 26 ou posterior (AlarmKit)
- Sons mais longos ocupam mais espaço. Um som de alarme de 10 minutos ocupa cerca de 50 MB.
""",
)

L["it"] = dict(
    subtitle="Svegliati col tuo ritornello",
    keywords="sveglia,suoneria,musica,canzone,video,audio,mp3,tagliare,mattina,orologio,suono,ripetere",
    promo="Svegliati con la musica che ami. Taglia solo il ritornello da un video o da un file audio: suonerà in loop finché non ti alzi.",
    description="""Svegliati con la musica che ami. Tieni solo la parte che vuoi: il ritornello, il passaggio, la frase che canti.

FUNZIONI PRINCIPALI

Svegliati con la tua parte preferita
Quasi nessuno vuole la canzone intera, solo una parte. Apri un video o un file audio, guarda la forma d'onda e trascina per scegliere il passaggio. Puoi ascoltarlo mentre lo regoli. La forma d'onda mostra dove il suono è forte e dove è piano.

Un passaggio breve funziona bene. La sveglia lo suona fino alla fine e poi ricomincia, finché non ti alzi. Venti o trenta secondi di ritornello spesso bastano.

I tuoi file
L'app usa l'audio che hai già: un file musicale, una registrazione vocale, il suono di un video salvato. Nessun abbonamento. Nessun catalogo da sfogliare.

Il suono di un video
Scegli un video dal Rullino e tieni solo il suono. Perfetto per video salvati o girati da te.

Importa file audio
Supporta MP3, AAC, WAV e M4A. Aprili dall'app File.

Il sistema di sveglie di Apple
L'app usa AlarmKit, il sistema di sveglie di Apple. La tua sveglia suona come quella dell'app Orologio. Non è un trucco in background che può fallire nel momento sbagliato.

Riconosci i tuoi suoni
Ogni sveglia mostra un'immagine del suo suono: un fotogramma del video o la copertina del file. Così distingui facilmente le sveglie.

Nessun limite di 40 secondi
Una suoneria dell'iPhone dura al massimo circa 40 secondi. Qui puoi prendere fino a 10 minuti da un video, e i file audio non hanno limiti di durata.

Condivisione
Invia audio o video a questa app da altre app.

Giorni di ripetizione
Scegli i giorni per ogni sveglia: feriali, weekend o quelli che vuoi.

Posticipa
Scegli 1, 2, 5 o 10 minuti con un tocco, o qualsiasi altro valore.

Modalità notte
Il tuo iPhone diventa un orologio da comodino. Cifre grandi e morbide, leggibili al buio.

FORMATI SUPPORTATI
MP3 / AAC / WAV / M4A / Audio da video (MOV, MP4)

NOTE
- Richiede iOS 26 o successivo (AlarmKit)
- Un suono più lungo occupa più spazio. Un suono di sveglia di 10 minuti occupa circa 50 MB.
""",
)

L["nl-NL"] = dict(
    subtitle="Wakker worden op je refrein",
    keywords="wekker,beltoon,muziek,liedje,nummer,video,audio,mp3,knippen,ochtend,klok,geluid,herhalen",
    promo="Word wakker met muziek waar je van houdt. Knip alleen het refrein uit een video of audiobestand en het speelt herhaald tot je opstaat.",
    description="""Word wakker met muziek waar je van houdt. Bewaar alleen het stuk dat je wilt: het refrein, de hook, de zin die je meezingt.

FUNCTIES

Word wakker met je favoriete stuk
Bijna niemand wil het hele nummer, alleen een stukje. Open een video of audiobestand, bekijk de golfvorm en sleep om het stuk te kiezen. Je kunt meeluisteren terwijl je het aanpast. De golfvorm laat zien waar het geluid hard en waar het zacht is.

Een kort stuk werkt goed. De wekker speelt het tot het einde en begint dan opnieuw, tot je opstaat. Twintig of dertig seconden refrein is vaak genoeg.

Je eigen bestanden
De app gebruikt audio die je al hebt: een muziekbestand, een spraakopname, het geluid van een opgeslagen video. Geen abonnement. Geen catalogus om door te zoeken.

Geluid uit een video
Kies een video uit je fotobibliotheek en houd alleen het geluid. Handig voor opgeslagen of zelf gefilmde video's.

Audiobestanden importeren
MP3, AAC, WAV en M4A werken allemaal. Open ze vanuit de Bestanden-app.

Het wekkersysteem van Apple
De app gebruikt AlarmKit, het wekkersysteem van Apple. Je wekker gaat af zoals die in de Klok-app. Geen achtergrondtruc die op het verkeerde moment faalt.

Herken je geluiden
Elke wekker toont een afbeelding van zijn geluid: een beeld uit je video of de hoes van je bestand. Zo houd je je wekkers makkelijk uit elkaar.

Geen limiet van 40 seconden
Een iPhone-beltoon mag maar ongeveer 40 seconden duren. Hier kun je tot 10 minuten uit een video halen, en audiobestanden hebben geen lengtelimiet.

Deelmenu
Stuur audio of video vanuit andere apps naar deze app.

Herhaaldagen
Kies de dagen voor elke wekker: doordeweeks, in het weekend of welke dagen je maar wilt.

Sluimeren
Kies met één tik 1, 2, 5 of 10 minuten, of elke andere waarde.

Nachtmodus
Je iPhone wordt een klok naast je bed. Grote, zachte cijfers, goed leesbaar in een donkere kamer.

ONDERSTEUNDE FORMATEN
MP3 / AAC / WAV / M4A / Geluid uit video (MOV, MP4)

OPMERKINGEN
- Vereist iOS 26 of nieuwer (AlarmKit)
- Een langer geluid neemt meer ruimte in. Een wekkergeluid van 10 minuten is ongeveer 50 MB.
""",
)

L["ko"] = dict(
    subtitle="좋아하는 부분으로 일어나는 알람",
    keywords="알람,알람음,기상,음악,노래,동영상,오디오,mp3,자르기,아침,시계,벨소리,모닝콜,반복",
    promo="좋아하는 음악으로 일어나세요. 동영상이나 오디오 파일에서 후렴만 잘라 두면, 일어날 때까지 반복해서 울려요.",
    description="""좋아하는 음악으로 일어나세요. 원하는 부분만 남길 수 있어요. 후렴, 훅, 따라 부르는 한 소절.

주요 기능

좋아하는 부분으로 기상
곡 전체가 필요한 사람은 많지 않아요. 원하는 건 그중 한 부분이죠. 동영상이나 오디오 파일을 열고 파형을 보면서 드래그해 구간을 고르세요. 조절하면서 들어볼 수 있어요. 파형을 보면 소리가 큰 곳과 조용한 곳을 알 수 있어요.

짧은 구간이 잘 맞아요. 알람은 끝까지 재생한 뒤 다시 처음부터, 일어날 때까지 반복해요. 후렴 20~30초면 충분한 경우가 많아요.

내가 가진 파일로
이미 가지고 있는 오디오를 사용해요. 음악 파일, 녹음한 목소리, 저장한 동영상의 소리. 구독도, 음악 카탈로그를 찾아볼 필요도 없어요.

동영상에서 소리만
사진 보관함의 동영상을 골라 소리만 남길 수 있어요. 저장한 동영상이나 직접 찍은 동영상에 잘 맞아요.

오디오 파일 가져오기
MP3, AAC, WAV, M4A를 지원해요. 파일 앱에서 바로 열 수 있어요.

Apple의 알람 시스템
Apple의 알람 시스템인 AlarmKit을 사용해요. 기본 시계 앱과 같은 방식으로 울려요. 중요할 때 실패할 수 있는 백그라운드 우회 방식이 아니에요.

소리를 한눈에
알람마다 소리의 이미지를 보여줘요. 사용한 동영상의 한 장면이나 파일의 앨범 아트가 나와서 알람을 쉽게 구분할 수 있어요.

40초 제한 없음
iPhone 벨소리는 약 40초까지만 쓸 수 있어요. 이 앱은 동영상에서 최대 10분, 오디오 파일은 길이 제한 없이 가져올 수 있어요.

공유 시트
다른 앱에서 공유 시트로 오디오나 동영상을 바로 보낼 수 있어요.

반복 요일
알람마다 요일을 고를 수 있어요. 평일만, 주말만, 원하는 요일 모두 가능해요.

다시 알림
1분, 2분, 5분, 10분을 한 번에 고르거나 원하는 값을 설정할 수 있어요.

나이트 모드
iPhone을 침대 옆 시계로 쓸 수 있어요. 어두운 방에서도 잘 보이는 크고 부드러운 숫자예요.

지원 형식
MP3 / AAC / WAV / M4A / 동영상의 오디오 (MOV, MP4)

참고
- iOS 26 이상 필요 (AlarmKit)
- 소리가 길수록 저장 공간을 더 사용해요. 10분짜리 알람 소리는 약 50MB예요.
""",
)

L["zh-Hans"] = dict(
    subtitle="用最爱的副歌叫醒你",
    keywords="闹钟,铃声,音乐,歌曲,视频,音频,剪辑,起床,早晨,时钟,自定义,mp3,循环,提取",
    promo="用你喜欢的音乐醒来。从视频或音频文件里只剪出副歌，它会一直循环播放，直到你起床。",
    description="""用你喜欢的音乐醒来。只留下你想要的部分：副歌、记忆点、你会跟着唱的那一句。

主要功能

在最爱的片段中醒来
很少有人想要整首歌，想要的只是其中一段。打开视频或音频文件，看着波形拖动来选择片段。调整时可以边听边改。波形会显示哪里响、哪里轻。

短一点的片段效果很好。闹钟会播放到结尾再从头开始，直到你起床。副歌的二三十秒通常就够了。

用你自己的文件
本应用使用你已有的音频：音乐文件、录下的声音、保存的视频里的声音。无需订阅，也不用在曲库里翻找。

从视频中取出声音
从相簿中选择视频，只保留声音。适合保存下来的视频或你自己拍的视频。

导入音频文件
支持 MP3、AAC、WAV 和 M4A。可以直接从"文件"App 打开。

基于 Apple 的闹钟系统
本应用使用 Apple 的闹钟系统 AlarmKit。你的闹钟和自带"时钟"App 用同样的方式响起，不是可能在关键时刻失灵的后台变通方案。

一眼认出你的声音
每个闹钟都会显示它的声音图片：视频中的一帧或文件的专辑封面，方便区分不同的闹钟。

没有 40 秒限制
iPhone 铃声最长约 40 秒。本应用可以从视频中截取最长 10 分钟，音频文件则没有长度限制。

共享表单
可以从其他 App 直接把音频或视频发送到本应用。

重复日期
为每个闹钟选择日期：工作日、周末或任意日子。

稍后提醒
一键选择 1、2、5 或 10 分钟，也可以设置任意时长。

夜间模式
让 iPhone 变成床头钟。数字大而柔和，在暗处也看得清。

支持的格式
MP3 / AAC / WAV / M4A / 视频中的音频（MOV、MP4）

注意事项
- 需要 iOS 26 或更高版本（AlarmKit）
- 声音越长，占用空间越多。10 分钟的闹钟声音约 50 MB。
""",
)

LIMITS = {"subtitle": 30, "keywords": 100, "promo": 170, "description": 4000}
BANNED = ["free", "gratuit", "kostenlos", "gratis", "grátis", "gratuito", "무료", "免费"]


def main():
    en = os.path.join(ROOT, "en-US")
    privacy = open(os.path.join(en, "privacy_url.txt"), encoding="utf-8").read()
    support = open(os.path.join(en, "support_url.txt"), encoding="utf-8").read()
    errors = []
    for loc, d in L.items():
        for k, lim in LIMITS.items():
            if len(d[k]) > lim:
                errors.append(f"{loc} {k}: {len(d[k])} > {lim}")
        low = (d["subtitle"] + d["keywords"] + d["promo"] + d["description"]).lower()
        errors += [f"{loc}: contains '{w}'" for w in BANNED if w in low]
        if " " in d["keywords"] or ", " in d["keywords"]:
            errors.append(f"{loc} keywords: contains spaces")
        out = os.path.join(ROOT, loc)
        os.makedirs(out, exist_ok=True)
        files = {"name.txt": "My Sound Alarm\n", "subtitle.txt": d["subtitle"] + "\n",
                 "keywords.txt": d["keywords"] + "\n", "promotional_text.txt": d["promo"] + "\n",
                 "description.txt": d["description"], "privacy_url.txt": privacy, "support_url.txt": support}
        for fn, body in files.items():
            with open(os.path.join(out, fn), "w", encoding="utf-8") as f:
                f.write(body)
        print(f"{loc:8} subtitle {len(d['subtitle']):2}/30  keywords {len(d['keywords']):3}/100  promo {len(d['promo']):3}/170  desc {len(d['description']):4}/4000")
    if errors:
        print("ERRORS:\n" + "\n".join(errors))
        sys.exit(1)


if __name__ == "__main__":
    main()
