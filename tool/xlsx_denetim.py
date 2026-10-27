"""1.30.4: Uygulamanın yazdığı örnek Excel'i bağımsız bir okuyucuyla
(openpyxl) açar ve içeriğini denetler. CI'da flutter testlerinden sonra çalışır.
"""
import sys
import zipfile

import openpyxl

YOL = "build/ornek_rapor.xlsx"
hatalar = []


def kontrol(kosul, mesaj):
    print(("TAMAM  " if kosul else "HATA   ") + mesaj, flush=True)
    if not kosul:
        hatalar.append(mesaj)
        print(f"::error title=Excel denetimi::{mesaj}", flush=True)


z = zipfile.ZipFile(YOL)
kontrol(z.testzip() is None, "zip bütün")
adlar = set(z.namelist())
kontrol("xl/drawings/drawing1.xml" not in adlar, "çizim parçası yok")
kontrol("xl/theme/theme1.xml" not in adlar, "tema parçası yok")

wb = openpyxl.load_workbook(YOL)
ws = wb.active
kontrol(ws.title == "Rapor", f"sayfa adı Rapor ({ws.title})")
kontrol(ws["A1"].value == "Hareket Geçmişi", f"A1 başlık ({ws['A1'].value})")
kontrol(ws["A1"].font.b and ws["A1"].font.sz == 14, "A1 kalın 14 pt")
kontrol(ws["A4"].value == "Toplam" and ws["B4"].value == 12, "özet: Toplam = 12 (sayı)")
kontrol(ws["A4"].font.b, "özet etiketi kalın")
bolum = ws["A7"]
kontrol(bolum.value == "KAMERA MONTAJ EKİBİ DEPOSU", f"bölüm başlığı ({bolum.value})")
kontrol(bolum.fill.fgColor.rgb in ("FFC8E6C9", "00C8E6C9"), f"bölüm yeşil ({bolum.fill.fgColor.rgb})")
kontrol(ws["A8"].value == 'Ağ ürünleri & "kayıt" <cihazları>', "özel karakterler")
kontrol(ws["A9"].value == "Tarih" and ws["E9"].value == "Konum", "sütun başlıkları")
kontrol(ws["A9"].fill.fgColor.rgb in ("FFE0E0E0", "00E0E0E0"), "sütun başlığı gri")
kontrol(ws["D10"].value == 1 and ws["D11"].value == 2.5, "sayılar sayı olarak")
kontrol(str(ws["E10"].value).startswith("=HYPERLINK("), f"bağlantı formülü ({ws['E10'].value})")
kontrol(ws["B11"].value == "ÇİĞDEM ŞÜKRÜ İĞNE", "Türkçe harfler")
kontrol(ws.column_dimensions["B"].width == 30, f"B sütunu 30 ({ws.column_dimensions['B'].width})")
kontrol(ws.column_dimensions["D"].width == 14, f"D sütunu en az 14 ({ws.column_dimensions['D'].width})")

sys.exit(1 if hatalar else 0)
