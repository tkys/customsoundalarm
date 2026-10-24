# プリセット音源クレジット

本ファイルには CustomSoundAlarm に同梱されているプリセット音源の出所を記録する。
App Store 配布物に含まれるため、ライセンス情報は正確に保持すること。

## PresetMarimba.caf — マリンバ

- **生成方法**: ffmpeg で合成（オリジナル）
- **ライセンス**: 権利リスクなし（オリジナル作品）
- **生成式**:
  ```
  ffmpeg -y -f lavfi -i "aevalsrc='0.85*sin(2*PI*(if(eq(floor(mod(t,1.6)/0.4),0),523.25,if(eq(floor(mod(t,1.6)/0.4),1),659.25,if(eq(floor(mod(t,1.6)/0.4),2),783.99,1046.5))))*t)*exp(-8*mod(t,0.4))':s=44100:d=28" -af "alimiter=limit=0.95" -ac 1 -c:a pcm_s16le -f caf PresetMarimba.caf
  ```
- **長さ**: 28秒

## PresetBell.caf — やわらかベル

- **生成方法**: ffmpeg で合成（オリジナル）
- **ライセンス**: 権利リスクなし（オリジナル作品）
- **生成式**:
  ```
  ffmpeg -y -f lavfi -i "aevalsrc='0.55*(sin(2*PI*659.25*t)+0.5*sin(2*PI*1318.5*t)+0.25*sin(2*PI*1977.75*t))*exp(-1.6*mod(t,2.4))':s=44100:d=28" -af "alimiter=limit=0.95" -ac 1 -c:a pcm_s16le -f caf PresetBell.caf
  ```
- **長さ**: 28秒

## PresetCrescendo.caf — クレッシェンド

- **生成方法**: ffmpeg で合成（オリジナル）
- **ライセンス**: 権利リスクなし（オリジナル作品）
- **生成式**:
  ```
  ffmpeg -y -f lavfi -i "aevalsrc='0.9*min(1,t/18)*(sin(2*PI*587.33*t)+0.4*sin(2*PI*880*t))*0.7*exp(-3*mod(t,1.2))':s=44100:d=28" -af "alimiter=limit=0.95" -ac 1 -c:a pcm_s16le -f caf PresetCrescendo.caf
  ```
- **長さ**: 28秒

## PresetBeep.caf — レトロビープ

- **生成方法**: ffmpeg で合成（オリジナル）
- **ライセンス**: 権利リスクなし（オリジナル作品）
- **生成式**:
  ```
  ffmpeg -y -f lavfi -i "aevalsrc='0.9*sin(2*PI*1046.5*t)*(if(lt(mod(t,1.4),0.12),exp(-14*mod(t,1.4)),if(between(mod(t,1.4),0.22,0.36),exp(-14*(mod(t,1.4)-0.22)),0)))':s=44100:d=28" -af "alimiter=limit=0.95" -ac 1 -c:a pcm_s16le -f caf PresetBeep.caf
  ```
- **長さ**: 28秒

## PresetAscending.caf — 上昇シーケンス

- **生成方法**: ffmpeg で合成（オリジナル）
- **ライセンス**: 権利リスクなし（オリジナル作品）
- **生成式**:
  ```
  ffmpeg -y -f lavfi -i "aevalsrc='0.85*sin(2*PI*(392+floor(mod(t,2.0)/0.25)*98)*t)*exp(-9*mod(t,0.25))':s=44100:d=28" -af "alimiter=limit=0.95" -ac 1 -c:a pcm_s16le -f caf PresetAscending.caf
  ```
- **長さ**: 28秒

## PresetDualTone.caf — デュアルトーン

- **生成方法**: ffmpeg で合成（オリジナル）
- **ライセンス**: 権利リスクなし（オリジナル作品）
- **生成式**:
  ```
  ffmpeg -y -f lavfi -i "aevalsrc='0.9*sin(2*PI*(if(lt(mod(t,0.7),0.35),880,1174.66))*t)*exp(-7*mod(t,0.35))':s=44100:d=28" -af "alimiter=limit=0.95" -ac 1 -c:a pcm_s16le -f caf PresetDualTone.caf
  ```
- **長さ**: 28秒

## PresetMusicBox.caf — オルゴール

- **生成方法**: ffmpeg で合成（オリジナル）
- **ライセンス**: 権利リスクなし（オリジナル作品）
- **生成式**:
  ```
  ffmpeg -y -f lavfi -i "aevalsrc='0.7*(sin(2*PI*(if(eq(floor(mod(t,4)/1),0),523.25,if(eq(floor(mod(t,4)/1),1),659.25,if(eq(floor(mod(t,4)/1),2),587.33,783.99))))*t)+0.3*sin(2*PI*(if(eq(floor(mod(t,4)/1),0),1046.5,if(eq(floor(mod(t,4)/1),1),1318.5,if(eq(floor(mod(t,4)/1),2),1174.66,1567.98))))*t))*exp(-2.5*mod(t,1))':s=44100:d=28" -af "alimiter=limit=0.95" -ac 1 -c:a pcm_s16le -f caf PresetMusicBox.caf
  ```
- **長さ**: 28秒

## PresetBackupLoud.caf — 最終アラーム用（最大音量・#109）

- **生成方法**: ffmpeg で合成（オリジナル）
- **ライセンス**: 権利リスクなし（オリジナル作品）
- **用途**: 「最終アラーム」専用。サウンド選択の一覧には出さない
- **狙い**: 高め（1568/2093 Hz + 倍音）で耳に刺さるビープを 25 秒。ピーク −1 dBFS、Integrated −8 LUFS 前後
- **生成式**:
  ```
  ffmpeg -y -f lavfi -i "aevalsrc='0.6*(sin(2*PI*(if(lt(mod(t,0.3),0.15),2093,1568))*t)+0.5*sin(4*PI*(if(lt(mod(t,0.3),0.15),2093,1568))*t)+0.25*sin(6*PI*(if(lt(mod(t,0.3),0.15),2093,1568))*t))*(if(lt(mod(t,0.3),0.15),0.5*(1-cos(2*PI*mod(t,0.3)/0.15)),0))':s=44100:d=25" -af "alimiter=limit=0.4:level=false,alimiter=limit=0.25:level=false,loudnorm=I=-9:TP=-1:LRA=7,volume=8dB,alimiter=limit=0.891:level=false" -ar 44100 -ac 1 -c:a pcm_s16le -f caf PresetBackupLoud.caf
  ```
- **計測**: Integrated −7.2 LUFS / True Peak −1.0 dBTP（ffmpeg ebur128）。無音区間を除く RMS −9.9 dBFS、ピーク −1.0 dBFS（アプリ内 `SoundLoudness`）
- **長さ**: 25秒
