# Alert sounds

The committed WAV files are short derivatives of these Freesound recordings. Both
source pages identify the recording and mark it as
[Creative Commons 0](https://creativecommons.org/publicdomain/zero/1.0/).

| Output | Recording | High-quality preview used | Preview SHA-256 |
| --- | --- | --- | --- |
| `bull-moo.wav` | [“Cow - Moan 2 - 96kHz.wav” by JarredGibb](https://freesound.org/s/233146/) | [MP3](https://cdn.freesound.org/previews/233/233146_4056007-hq.mp3) | `13d25500c553888c4c6b5c6f6b60d8763886bf0955b952196add20f79d97c54d` |
| `bear-growl.wav` | [“Growl” by whirlproductions](https://freesound.org/s/752374/) | [MP3](https://cdn.freesound.org/previews/752/752374_1598896-hq.mp3) | `8fa75cc0c801a4fc4b1ef4eff9f4279b6bf5dc5bec0abc3e38aa203e386d0dd9` |

The audio edits represented by the committed files are:

```sh
ffmpeg -i 233146_4056007-hq.mp3 \
  -af "atrim=start=0.40:end=1.73,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.02,afade=t=out:st=1.18:d=0.15,loudnorm=I=-20:TP=-3:LRA=5,atrim=end=1.33" \
  -t 1.33 -ar 44100 -ac 1 -c:a pcm_s16le bull-moo.wav

ffmpeg -i 752374_1598896-hq.mp3 \
  -af "atrim=start=0:end=0.73,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.02,afade=t=out:st=0.58:d=0.15,loudnorm=I=-20:TP=-3:LRA=5,atrim=end=0.73" \
  -t 0.73 -ar 44100 -ac 1 -c:a pcm_s16le bear-growl.wav
```

The outputs are 44.1 kHz, mono, 16-bit PCM. Their checksums are:

| Output | File SHA-256 | PCM payload SHA-256 |
| --- | --- | --- |
| `bull-moo.wav` | `1a836fef44c6830df53d6007f401e9e07a9ddd3414bd446c15cd594eb4687129` | `79e535c433b24a6b1a2f3d23ca5a5154e30658f2e415e554a8b3fb9df92c8315` |
| `bear-growl.wav` | `78719a041634af7581235914d7b8e06b298e978a985a32c5eef1446a0ed06a24` | `b4e13388d4cefd9dede17309c53b1868c0fe7f6b5e4273abe2b0106004082b0a` |

The preview inputs are not committed. This repository therefore does not include
or claim an offline-reproducible generator. The committed containers record
`Lavf62.12.101` in the `ISFT` metadata. Other FFmpeg versions can change those
container bytes even when the PCM payload is identical; use both checksums when
auditing the committed assets.
