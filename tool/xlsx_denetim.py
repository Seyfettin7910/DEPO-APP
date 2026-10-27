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


def renk(h):
    return (h.fill.fgColor.rgb or "")[-6:] if h.fill and h.fill.fill_type == "solid" else None


kontrol(ws.title == "Rapor", f"sayfa adı Rapor ({ws.title})")
kontrol(ws["A1"].value == "Hareket Geçmişi", f"A1 başlık ({ws['A1'].value})")
kontrol(ws["A1"].font.b and ws["A1"].font.sz == 16, "A1 kalın 16 pt")
kontrol(ws["A2"].font.color is not None and ws["A2"].font.color.rgb.endswith("616161"), "alt başlık gri")
kontrol(ws["E2"].border.bottom.style == "thin", "alt başlığın altında çizgi")
kontrol(ws["A4"].value == "Toplam" and ws["B4"].value == "Dönem", "özet etiketleri yan yana")
kontrol(renk(ws["A4"]) == "E8F5E9", f"özet kutusu yeşil ({renk(ws['A4'])})")
kontrol(ws["A5"].value == 12 and ws["A5"].font.b and ws["A5"].font.sz == 14, "özet değeri sayı, kalın 14")
kontrol(ws["A7"].value == "KAMERA MONTAJ EKİBİ DEPOSU", f"bölüm başlığı ({ws['A7'].value})")
kontrol(renk(ws["A7"]) == "C8E6C9" and renk(ws["E7"]) == "C8E6C9", "bölüm başlığı yeşil, tablo genişliğince")
kontrol(ws["A8"].value == 'Ağ ürünleri & "kayıt" <cihazları>', "özel karakterler")
kontrol(ws["A9"].value == "Tarih" and ws["E9"].value == "Konum", "sütun başlıkları")
kontrol(renk(ws["A9"]) == "E0E0E0" and ws["A9"].font.b, "sütun başlığı gri ve kalın")
kontrol(all(ws[f"{c}9"].border.left.style == "thin" for c in "ABCDE"), "sütun başlığı çerçeveli")
kontrol(renk(ws["A10"]) is None and renk(ws["A11"]) == "F5F5F5", "satırlar bir beyaz bir açık gri")
kontrol(ws["C11"].border.left.style == "thin", "boş hücre de çerçeveli")
kontrol(ws["A10"].alignment.wrap_text, "uzun yazı alt satıra kayar")
kontrol(ws["D10"].value == 1 and ws["D11"].value == 2.5, "sayılar sayı olarak")
kontrol(str(ws["E10"].value).startswith("=HYPERLINK("), f"bağlantı formülü ({ws['E10'].value})")
kontrol(ws["E10"].font.u == "single", "bağlantı altı çizili")
kontrol(ws["B11"].value == "ÇİĞDEM ŞÜKRÜ İĞNE", "Türkçe harfler")
kontrol(ws.freeze_panes == "A10", f"tablo başlığı sabit ({ws.freeze_panes})")
kontrol(str(ws.print_title_rows).replace("$", "") == "9:9", f"yazdırmada her sayfada başlık ({ws.print_title_rows})")
kontrol(ws.page_setup.fitToWidth == 1, "yazdırma: sayfa genişliğine sığdır")
kontrol("DEPO YÖNETİM SİSTEMİ" in (ws.oddFooter.right.text or ""), "alt bilgi")
kontrol(ws.column_dimensions["B"].width == 30, f"B sütunu 30 ({ws.column_dimensions['B'].width})")
kontrol(ws.column_dimensions["D"].width == 14, f"D sütunu en az 14 ({ws.column_dimensions['D'].width})")

sys.exit(1 if hatalar else 0)
