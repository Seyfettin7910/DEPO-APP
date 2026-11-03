# Kılavuz videosu seslendirmesi (geçici dal; video bitince silinir).
import asyncio, csv, os, sys
import edge_tts

SESLER = {"emel": "tr-TR-EmelNeural", "ahmet": "tr-TR-AhmetNeural"}

async def main():
    satirlar = [l.rstrip("\n").split("\t", 1) for l in open("tool/video_metin.tsv", encoding="utf-8") if l.strip()]
    for ad, ses in SESLER.items():
        os.makedirs(f"out/{ad}", exist_ok=True)
        for kimlik, metin in satirlar:
            for deneme in range(4):
                try:
                    await edge_tts.Communicate(metin, ses, rate="+3%").save(f"out/{ad}/{kimlik}.mp3")
                    break
                except Exception as e:
                    print("tekrar", kimlik, e, file=sys.stderr)
                    await asyncio.sleep(3)
            else:
                raise SystemExit(f"olmadı: {ad} {kimlik}")
            print(ad, kimlik)

asyncio.run(main())
