import unittest
from calculator import add
class CI(unittest.TestCase):
    def test_zero(self): self.assertEqual(add(0, 5), 5)
    def test_decimal(self): self.assertAlmostEqual(add(0.1, 0.2), 0.3)
