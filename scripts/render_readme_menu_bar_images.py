#!/usr/bin/env python3
"""Render localized README menu bar mock screenshots.

The README files intentionally use static mock screenshots. This script keeps
the menu bar image reproducible so localized README pages do not share one
hard-coded language image.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
IMAGES_DIR = ROOT / "docs" / "images"
W, H = 760, 1234

FONT_CANDIDATES = [
    Path("/System/Library/Fonts/Supplemental/Arial Unicode.ttf"),
    Path("/Library/Fonts/Arial Unicode.ttf"),
    Path("/System/Library/Fonts/Hiragino Sans GB.ttc"),
    Path("/System/Library/Fonts/SFNS.ttf"),
]


def font(size: int) -> ImageFont.FreeTypeFont:
    for candidate in FONT_CANDIDATES:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size=size)
    return ImageFont.load_default()


F_TITLE = font(34)
F_SUBTITLE = font(18)
F_BUTTON = font(23)
F_SECTION = font(24)
F_EMAIL = font(25)
F_META = font(21)
F_SMALL = font(18)
F_BADGE = font(17)


@dataclass(frozen=True)
class Strings:
    filename: str
    subtitle: str
    sync_now: str
    open_dashboard: str
    updated: str
    active_section: str
    accounts_section: str
    group_name: str
    reset_credit: str
    reset_1: str
    reset_2: str
    switch: str
    weekly: str
    five_hour: str
    usage_current: str
    usage_team: str
    api_key: str = "API Key"


LOCALIZED: dict[str, Strings] = {
    "en": Strings(
        filename="menu-bar.png",
        subtitle="Menu bar dashboard · Accounts 5 · Available 2 · Usage 91% · Intelligent",
        sync_now="Sync now",
        open_dashboard="Open dashboard",
        updated="Updated just now",
        active_section="Active account",
        accounts_section="Accounts",
        group_name="Default",
        reset_credit="2 resets",
        reset_1="Reset 1 expires: 2026/7/30 20:03 GMT+8",
        reset_2="Reset 2 expires: 2026/7/30 20:03 GMT+8",
        switch="Switch",
        weekly="W 91% 7/7 09:55",
        five_hour="5h 94% 7/1 12:09",
        usage_current="W 91% 7/7 09:55",
        usage_team="W 100% 7/8 11:56",
    ),
    "zh-Hant": Strings(
        filename="menu-bar.zh-Hant.png",
        subtitle="選單列儀表板・帳號 5・可用 2・用量 91%・智能切換",
        sync_now="立即同步",
        open_dashboard="開啟主畫面",
        updated="現在 前更新",
        active_section="目前帳號",
        accounts_section="帳號",
        group_name="Default",
        reset_credit="可重置 2 次",
        reset_1="第 1 次期限：2026/7/30 20:03:24 GMT+8",
        reset_2="第 2 次期限：2026/7/30 20:03:24 GMT+8",
        switch="切換",
        weekly="W 91% 7/7 09:55",
        five_hour="5h 94% 7/1 12:09",
        usage_current="W 91% 7/7 09:55",
        usage_team="W 100% 7/8 11:56",
    ),
    "zh-Hans": Strings(
        filename="menu-bar.zh-Hans.png",
        subtitle="菜单栏仪表板・账号 5・可用 2・用量 91%・智能切换",
        sync_now="立即同步",
        open_dashboard="打开主界面",
        updated="刚刚更新",
        active_section="当前账号",
        accounts_section="账号",
        group_name="Default",
        reset_credit="可重置 2 次",
        reset_1="第 1 次期限：2026/7/30 20:03:24 GMT+8",
        reset_2="第 2 次期限：2026/7/30 20:03:24 GMT+8",
        switch="切换",
        weekly="W 91% 7/7 09:55",
        five_hour="5h 94% 7/1 12:09",
        usage_current="W 91% 7/7 09:55",
        usage_team="W 100% 7/8 11:56",
    ),
    "ja": Strings(
        filename="menu-bar.ja.png",
        subtitle="メニューバーダッシュボード・アカウント 5・利用可能 2・使用量 91%・インテリジェント",
        sync_now="今すぐ同期",
        open_dashboard="メイン画面を開く",
        updated="たった今更新",
        active_section="現在のアカウント",
        accounts_section="アカウント",
        group_name="Default",
        reset_credit="リセット 2回",
        reset_1="リセット1回目の期限：2026/7/30 20:03 GMT+8",
        reset_2="リセット2回目の期限：2026/7/30 20:03 GMT+8",
        switch="切り替え",
        weekly="W 91% 7/7 09:55",
        five_hour="5h 94% 7/1 12:09",
        usage_current="W 91% 7/7 09:55",
        usage_team="W 100% 7/8 11:56",
    ),
    "ko": Strings(
        filename="menu-bar.ko.png",
        subtitle="메뉴 막대 대시보드・계정 5・사용 가능 2・사용량 91%・지능형 전환",
        sync_now="지금 동기화",
        open_dashboard="메인 화면 열기",
        updated="방금 업데이트",
        active_section="현재 계정",
        accounts_section="계정",
        group_name="Default",
        reset_credit="초기화 2회",
        reset_1="1번째 초기화 만료: 2026/7/30 20:03 GMT+8",
        reset_2="2번째 초기화 만료: 2026/7/30 20:03 GMT+8",
        switch="전환",
        weekly="W 91% 7/7 09:55",
        five_hour="5h 94% 7/1 12:09",
        usage_current="W 91% 7/7 09:55",
        usage_team="W 100% 7/8 11:56",
    ),
    "fr": Strings(
        filename="menu-bar.fr.png",
        subtitle="Tableau menu bar · Comptes 5 · Disponibles 2 · Usage 91 % · Intelligent",
        sync_now="Synchroniser",
        open_dashboard="Ouvrir le tableau",
        updated="Mis à jour maintenant",
        active_section="Compte actif",
        accounts_section="Comptes",
        group_name="Default",
        reset_credit="2 réinitialisations",
        reset_1="Expiration reset 1 : 30/07/2026 20:03 GMT+8",
        reset_2="Expiration reset 2 : 30/07/2026 20:03 GMT+8",
        switch="Changer",
        weekly="W 91 % 07/07 09:55",
        five_hour="5h 94 % 01/07 12:09",
        usage_current="W 91 % 07/07 09:55",
        usage_team="W 100 % 08/07 11:56",
    ),
    "es": Strings(
        filename="menu-bar.es.png",
        subtitle="Panel de barra de menú · Cuentas 5 · Disponibles 2 · Uso 91 % · Inteligente",
        sync_now="Sincronizar",
        open_dashboard="Abrir panel",
        updated="Actualizado ahora",
        active_section="Cuenta activa",
        accounts_section="Cuentas",
        group_name="Default",
        reset_credit="2 restablecimientos",
        reset_1="Vence rest. 1: 30/7/2026 20:03 GMT+8",
        reset_2="Vence rest. 2: 30/7/2026 20:03 GMT+8",
        switch="Cambiar",
        weekly="W 91 % 7/7 09:55",
        five_hour="5h 94 % 1/7 12:09",
        usage_current="W 91 % 7/7 09:55",
        usage_team="W 100 % 8/7 11:56",
    ),
}


def text_width(draw: ImageDraw.ImageDraw, text: str, fnt: ImageFont.ImageFont) -> int:
    box = draw.textbbox((0, 0), text, font=fnt)
    return box[2] - box[0]


def fit_text(draw: ImageDraw.ImageDraw, text: str, fnt: ImageFont.ImageFont, max_width: int) -> str:
    if text_width(draw, text, fnt) <= max_width:
        return text
    ellipsis = "…"
    while text and text_width(draw, text + ellipsis, fnt) > max_width:
        text = text[:-1]
    return text + ellipsis


def rounded(draw: ImageDraw.ImageDraw, xy: tuple[int, int, int, int], radius: int, fill, outline=None, width: int = 1) -> None:
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)


def make_background() -> Image.Image:
    img = Image.new("RGB", (W, H), "#07131d")
    px = img.load()
    for y in range(H):
        for x in range(W):
            blue = int(20 + 28 * (1 - y / H) + 18 * (x / W))
            green = int(18 + 24 * (1 - y / H))
            red = int(6 + 12 * (x / W))
            px[x, y] = (red, green, blue)
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((-220, 740, 530, 1460), fill=(20, 136, 128, 55))
    gd.ellipse((240, -220, 980, 420), fill=(25, 120, 255, 34))
    glow = glow.filter(ImageFilter.GaussianBlur(70))
    return Image.alpha_composite(img.convert("RGBA"), glow)


def paste_icon(canvas: Image.Image, x: int, y: int, size: int) -> None:
    icon_path = IMAGES_DIR / "app-icon.png"
    icon = Image.open(icon_path).convert("RGBA").resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle((0, 0, size, size), radius=30, fill=255)
    canvas.alpha_composite(icon, (x, y), source=(0, 0, size, size))
    # The source icon already has rounded corners; mask kept for future asset swaps.


def draw_button(draw: ImageDraw.ImageDraw, x: int, y: int, w: int, label: str, icon: str = "") -> None:
    rounded(draw, (x, y, x + w, y + 52), 10, fill=(48, 60, 74, 230))
    text = f"{icon}  {label}" if icon else label
    draw.text((x + 18, y + 12), fit_text(draw, text, F_BUTTON, w - 28), fill=(238, 245, 252), font=F_BUTTON)


def draw_badge(draw: ImageDraw.ImageDraw, x: int, y: int, label: str, fill=(24, 118, 213, 220), text_fill=(50, 162, 255)) -> int:
    pad_x = 12
    w = text_width(draw, label, F_BADGE) + pad_x * 2
    rounded(draw, (x, y, x + w, y + 31), 15, fill=fill)
    draw.text((x + pad_x, y + 4), label, fill=text_fill, font=F_BADGE)
    return w


def draw_account_card(
    draw: ImageDraw.ImageDraw,
    x: int,
    y: int,
    w: int,
    h: int,
    strings: Strings,
    email: str,
    plan: str | None,
    active: bool,
    warning: bool,
    show_reset: bool,
    switch: bool,
    usage: str,
) -> None:
    fill = (32, 86, 134, 245) if active else (49, 58, 61, 238)
    rounded(draw, (x, y, x + w, y + h), 22, fill=fill)

    dot = (30, 141, 255) if active else (112, 126, 133)
    draw.ellipse((x + 22, y + 60, x + 38, y + 76), fill=dot)
    draw.text((x + 58, y + 23), fit_text(draw, email, F_EMAIL, w - 260), fill=(236, 244, 252), font=F_EMAIL)
    email_w = min(text_width(draw, email, F_EMAIL), w - 280)
    draw.text((x + 66 + email_w, y + 24), "✦", fill=(38, 149, 255), font=F_EMAIL)
    if plan:
        draw_badge(draw, x + min(390, 66 + email_w + 36), y + 25, plan)
    if warning:
        draw.ellipse((x + w - 154, y + 33, x + w - 132, y + 55), fill=(255, 165, 48))
        draw.text((x + w - 147, y + 30), "!", fill=(23, 34, 42), font=F_SMALL)

    if switch:
        rounded(draw, (x + w - 124, y + 18, x + w - 24, y + 58), 10, fill=(87, 101, 116, 225))
        draw.text((x + w - 114, y + 24), fit_text(draw, strings.switch, F_SMALL, 82), fill=(250, 253, 255), font=F_SMALL)
    else:
        draw.ellipse((x + w - 52, y + 27, x + w - 22, y + 57), fill=(35, 147, 255))
        draw.text((x + w - 46, y + 25), "✓", fill=(5, 24, 39), font=F_META)

    draw.text((x + 58, y + 62), fit_text(draw, f"{usage}  ·  {strings.five_hour}", F_META, w - 120), fill=(184, 205, 226), font=F_META)

    if show_reset:
        draw.text((x + 58, y + 101), strings.reset_credit, fill=(42, 154, 255), font=F_META)
        draw.text((x + 58, y + 137), fit_text(draw, strings.reset_1, F_SMALL, w - 100), fill=(205, 220, 235), font=F_SMALL)
        draw.text((x + 58, y + 166), fit_text(draw, strings.reset_2, F_SMALL, w - 100), fill=(205, 220, 235), font=F_SMALL)


def render(strings: Strings) -> None:
    img = make_background()
    draw = ImageDraw.Draw(img, "RGBA")

    # Main popover shell
    rounded(draw, (20, 25, 740, 1210), 32, fill=(9, 22, 34, 230), outline=(91, 128, 166, 190), width=1)
    draw.rounded_rectangle((710, 70, 730, 394), radius=10, fill=(156, 166, 176, 210))

    paste_icon(img, 50, 54, 88)
    draw.text((160, 68), "Codex Pool", fill=(241, 248, 255), font=F_TITLE)
    draw.text((160, 110), fit_text(draw, strings.subtitle, F_SUBTITLE, 500), fill=(174, 190, 210), font=F_SUBTITLE)

    draw.ellipse((646, 60, 704, 118), outline=(96, 111, 124, 180), width=2, fill=(46, 58, 66, 230))
    draw.text((671, 78), "!", fill=(255, 165, 47), font=F_BUTTON)

    draw_button(draw, 50, 165, 195, strings.sync_now, "↻")
    draw_button(draw, 255, 165, 270, strings.open_dashboard)

    draw.text((50, 240), strings.updated, fill=(181, 194, 207), font=F_SECTION)

    # Active section
    rounded(draw, (50, 294, 710, 597), 26, fill=(38, 49, 52, 235), outline=(87, 102, 108, 180), width=1)
    draw.text((75, 324), strings.active_section, fill=(205, 216, 226), font=F_SECTION)
    draw_account_card(
        draw,
        75,
        367,
        610,
        190,
        strings,
        "demo.pro@example.com",
        "Pro",
        True,
        False,
        True,
        False,
        strings.usage_current,
    )

    # Accounts section
    rounded(draw, (50, 624, 710, 1155), 26, fill=(38, 49, 52, 235), outline=(87, 102, 108, 180), width=1)
    draw.text((75, 654), strings.accounts_section, fill=(205, 216, 226), font=F_SECTION)
    draw.text((595, 654), strings.group_name, fill=(232, 240, 248), font=F_SECTION)

    draw_account_card(
        draw,
        75,
        697,
        610,
        105,
        strings,
        "demo.pro@example.com",
        "Pro",
        True,
        False,
        False,
        True,
        strings.usage_current,
    )
    draw_account_card(
        draw,
        75,
        820,
        610,
        190,
        strings,
        "team.plus@example.com",
        "Plus",
        False,
        True,
        True,
        True,
        strings.usage_team,
    )
    draw_account_card(
        draw,
        75,
        1027,
        610,
        102,
        strings,
        "relay-key",
        strings.api_key,
        False,
        True,
        False,
        True,
        "W 100%",
    )

    output = IMAGES_DIR / strings.filename
    img.convert("RGB").save(output, quality=95, optimize=True)
    print(output.relative_to(ROOT))


def main() -> None:
    for strings in LOCALIZED.values():
        render(strings)


if __name__ == "__main__":
    main()
