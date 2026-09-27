import unittest
from collect_bullet_evidence import parse_render


class ReceiptTest(unittest.TestCase):
    def test_measured_values_not_historical_constants(self):
        text = ('PASS bullet pixels: tiers=32/64/128/256/512; representative '
                'visible=126 commands=134 pixels=596296 CRC=4f429e0b\n'
                'PASS bullet RTL: 596296 pixels COPY=587520 KEY=8296 ALPHA=432 FILL=48 stalls=70154\n'
                'PASS preview512: tick=0 visible=511 commands=519 CRC=4ff15b5e\n'
                'PASS preview512: tick=90 visible=509 commands=517 CRC=66e7dce8\n'
                'PASS preview512: tick=180 visible=510 commands=518 CRC=72172c5a\n')
        metrics = parse_render(text)
        self.assertEqual(metrics['frame_crc32'], '4f429e0b')
        self.assertEqual(metrics['rtl_pixel_operations'], 596296)
        self.assertEqual(metrics['previews_512'][1]['visible'], 509)
        for invalid in ('', text.replace('PASS bullet RTL: 596296', 'PASS bullet RTL: 596297'),
                        text.replace('PASS preview512: tick=180', 'FAIL preview512: tick=180')):
            with self.assertRaises(ValueError):
                parse_render(invalid)


if __name__ == '__main__':
    unittest.main()
