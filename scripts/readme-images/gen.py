"""README·사용 안내서용 그림의 HTML 을 만든다 (make.sh 가 부른다).
  python3 gen.py <작업 폴더>   — <작업 폴더>/syms.json 을 읽어 hero.html, settings-menubar-{en,ko,zh}.html 을 쓴다.
앱 목록은 예시 앱이다. 화면 문구가 바뀌면 아래 T 의 문구를 Localizable.xcstrings 와 맞춘다.
"""
import html, json, os, sys
work = sys.argv[1]
syms = json.load(open(os.path.join(work, 'syms.json')))
def sym(name, h=16, color=None, extra=''):
    s = syms[name]; w = s['w'] * h / s['h']
    c = f'color:{color};' if color else ''
    return (f'<i class="s" style="width:{w:.1f}px;height:{h}px;{c}{extra}'
            f'-webkit-mask-image:url(data:image/png;base64,{s["png"]})"></i>')
BASE = '''<!doctype html><meta charset="utf-8"><style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{background:transparent}
body{font-family:-apple-system,"SF Pro Text","Apple SD Gothic Neo","PingFang SC",sans-serif;-webkit-font-smoothing:antialiased}
.s{display:inline-block;background:currentColor;-webkit-mask-size:contain;-webkit-mask-repeat:no-repeat;-webkit-mask-position:center;flex:none}
%s</style>%s'''

# ---------- 메뉴바 전후 비교 ----------
def bar(items):
    return '<div class="bar">' + ''.join(items) + '</div>'
def ic(name, h=15, cls=''):
    return f'<span class="ic {cls}">{sym(name, h)}</span>'
system = [ic('switch.2', 14), ic('wifi', 13), ic('battery.100percent', 12), '<span class="clock">9:41</span>']
hidden = bar([ic('cloud.fill', 12), ic('curtains.closed', 15, 'ours')] + system)
expanded = bar([ic('music.note', 15, 'rev'), ic('paperplane.fill', 14, 'rev'), ic('doc.on.clipboard.fill', 16, 'rev'),
                ic('cloud.fill', 12), ic('curtains.open', 15, 'ours'),
                ic('bolt.fill', 15, 'rev'), ic('moon.fill', 14, 'rev')] + system)
hero_css = '''
.wrap{width:860px;padding:34px 40px 36px;border-radius:18px;
  background:radial-gradient(120% 140% at 0% 0%,#3b4fd8 0%,#5b3fb8 38%,#b0437f 72%,#f08a4b 100%)}
.bar{height:36px;border-radius:10px;background:rgba(18,18,24,.62);display:flex;align-items:center;justify-content:flex-end;
  gap:17px;padding:0 16px;color:#fff;box-shadow:0 6px 18px rgba(0,0,0,.25)}
.ic{display:inline-flex;align-items:center;justify-content:center;height:26px;min-width:20px}
.ic.ours{background:rgba(255,255,255,.2);border-radius:7px;padding:0 8px;box-shadow:0 0 0 1.5px rgba(255,255,255,.75)}
.ic.rev{color:#ffd66b}
.clock{font-size:13.5px;font-weight:500;letter-spacing:.2px}
.mid{height:66px;display:flex;align-items:center;justify-content:flex-end;color:#fff;padding-right:219px;position:relative}
.mid .line{position:absolute;right:245px;top:6px;bottom:10px;width:2px;background:rgba(255,255,255,.75);border-radius:2px}
.mid .tip{position:absolute;right:240px;bottom:6px;width:0;height:0;border-left:6px solid transparent;border-right:6px solid transparent;border-top:9px solid rgba(255,255,255,.85)}
.mid .click{position:absolute;right:196px;top:18px}
'''
hero = f'<div class="wrap">{hidden}<div class="mid"><span class="line"></span><span class="tip"></span><span class="click">{sym("cursorarrow.click.2", 28)}</span></div>{expanded}</div>'
open(os.path.join(work, 'hero.html'), 'w').write(BASE % (hero_css, hero))

# ---------- 설정 > 메뉴바 관리 (예시 앱) ----------
T = {
 'en': dict(title='Settings', tabs=['Menu Bar', 'General', 'Diagnostics'], search='Search apps',
            filters=['Menu Bar', 'Running', 'Hidden', 'All'], shown='Shown (3)', hiddenh='Hidden (2)', sysh='System Icons',
            running='Running', me='This app — always shown', battery='Battery',
            sysfoot='When off, that icon is hidden too while hiding is on. The clock and Control Center are never hidden.',
            state='Hiding', count='5 apps · 2 hidden', edit='Edit Order', off='Turn Hiding Off',
            note="Turn a switch off to hide that app's icon. Items added to the menu bar from Control Center (such as Timer) are always hidden while hiding is on."),
 'ko': dict(title='설정', tabs=['메뉴바 관리', '일반', '진단'], search='앱 이름 검색',
            filters=['메뉴바', '실행 중', '숨긴 앱', '전체'], shown='표시 3개', hiddenh='숨김 2개', sysh='시스템 아이콘',
            running='실행 중', me='이 앱 — 항상 표시', battery='배터리',
            sysfoot='끄면 숨기기가 켜져 있는 동안 그 아이콘도 숨깁니다. 시계와 제어 센터는 숨기지 않습니다.',
            state='숨김 적용 중', count='전체 5개 · 숨김 2개', edit='순서 편집', off='숨기기 끄기',
            note='스위치를 끄면 그 앱의 아이콘이 숨겨집니다. 제어 센터에서 메뉴바로 꺼낸 항목(타이머 등)은 숨김 중에는 항상 숨겨집니다.'),
 'zh': dict(title='设置', tabs=['菜单栏管理', '通用', '诊断'], search='搜索 App 名称',
            filters=['菜单栏', '正在运行', '已隐藏', '全部'], shown='显示（3）', hiddenh='隐藏（2）', sysh='系统图标',
            running='正在运行', me='这个 App — 始终显示', battery='电池',
            sysfoot='关闭后，在隐藏开启期间该图标也会被隐藏。时钟和控制中心不会被隐藏。',
            state='隐藏中', count='共 5 个 · 隐藏 2 个', edit='编辑顺序', off='关闭隐藏',
            note='关闭开关即可隐藏该 App 的图标。从控制中心添加到菜单栏的项目（如计时器）在隐藏期间始终隐藏。'),
}
set_css = '''
.win{width:580px;border-radius:13px;background:#1f1f1f;color:#ececec;overflow:hidden;
  box-shadow:0 0 0 1px rgba(255,255,255,.14) inset;font-size:13px}
.tb{height:32px;background:#2b2b2b;border-bottom:1px solid #151515;display:flex;align-items:center;padding:0 12px;gap:8px}
.tl{width:12px;height:12px;border-radius:50%}
.tb b{margin-left:8px;font-weight:600;color:#cfcfcf;font-size:13px}
.seg{display:inline-flex;background:#333;border-radius:7px;overflow:hidden}
.seg span{padding:4px 13px;font-size:13px;color:#eee;white-space:nowrap}
.seg span.on{background:#2a7bf6;color:#fff;border-radius:7px}
.tabs{display:flex;justify-content:center;padding:14px 0 16px}
.tabs .seg span{padding:5px 22px}
.row1{display:flex;gap:8px;padding:0 16px 12px;align-items:center}
.search{flex:1;height:26px;border-radius:7px;background:#161616;border:1px solid #3a3a3a;color:#8d8d8d;padding:0 8px;display:flex;align-items:center}
.box{margin:0 16px;border:1px solid #3b3b3b;border-radius:10px;padding:0 16px 14px;background:#222}
.h{font-size:11.5px;font-weight:600;color:#a9a9a9;padding:10px 0 7px;border-bottom:1px solid #3a3a3a}
.h.gap{margin-top:14px}
.r{display:flex;align-items:center;gap:12px;padding:7px 0}
.r .txt{flex:1;border-bottom:1px solid #353535;margin:-7px 0;padding:7px 0;display:flex;align-items:center}
.r .nm{flex:1}
.r .nm small{display:block;color:#9a9a9a;font-size:10.5px;margin-top:1px}
.app{width:22px;height:22px;border-radius:6px;display:flex;align-items:center;justify-content:center;color:#fff;flex:none}
.sysic{width:22px;display:flex;justify-content:center;color:#f2f2f2}
.tg{width:42px;height:20px;border-radius:10px;background:#2a7bf6;position:relative;flex:none}
.tg::after{content:"";position:absolute;top:1.5px;right:1.5px;width:25px;height:17px;border-radius:9px;background:#fff}
.tg.off{background:#3c3c3c}.tg.off::after{right:auto;left:1.5px}
.tg.dim{background:#2a5cb4}
.foot{font-size:11px;color:#9a9a9a;padding-top:8px}
.bottom{display:flex;align-items:center;gap:9px;padding:12px 16px 6px}
.bottom .st{flex:1}
.bottom .ct{color:#9a9a9a}
.btn{background:#3a3a3a;border-radius:6px;padding:3.5px 12px;color:#f0f0f0}
.note{font-size:11px;color:#9a9a9a;padding:2px 16px 14px;line-height:1.35}
'''
def app(color, glyph, h=12):
    return f'<span class="app" style="background:{color}">{sym(glyph, h)}</span>'
def row(icon, name, sub, tg):
    small = f'<small>{html.escape(sub)}</small>' if sub else ''
    return f'<div class="r">{icon}<div class="txt"><div class="nm">{html.escape(name)}{small}</div><span class="tg {tg}"></span></div></div>'
def settings(t):
    seg = lambda items, on: '<span class="seg">' + ''.join(f'<span class="{"on" if i == on else ""}">{html.escape(x)}</span>' for i, x in enumerate(items)) + '</span>'
    body = f'''<div class="win">
<div class="tb"><span class="tl" style="background:#ff5f57"></span><span class="tl" style="background:#febc2e"></span><span class="tl" style="background:#28c840"></span><b>{t["title"]}</b></div>
<div class="tabs">{seg(t["tabs"], 0)}</div>
<div class="row1"><div class="search">{t["search"]}</div>{seg(t["filters"], 0)}</div>
<div class="box">
<div class="h">{t["shown"]}</div>
{row(app("linear-gradient(#5aa9ff,#2f6fe0)", "cloud.fill", 9), "Cloud Sync", t["running"], "")}
{row(app("linear-gradient(#ff7a9c,#e0345e)", "music.note", 13), "Music Remote", t["running"], "")}
{row(app("linear-gradient(#3fb7a4,#1f7f78)", "curtains.closed", 11), "MenuBarManager", t["me"], "dim")}
<div class="h gap">{t["hiddenh"]}</div>
{row(app("linear-gradient(#ffb44a,#e9792a)", "doc.on.clipboard.fill", 13), "Clipboard Keeper", t["running"], "off")}
{row(app("linear-gradient(#9b7bff,#6a44d8)", "rectangle.split.2x1.fill", 10), "Window Snap", t["running"], "off")}
<div class="h gap">{t["sysh"]}</div>
{row('<span class="sysic">' + sym("wifi", 12) + '</span>', "Wi-Fi", "", "")}
{row('<span class="sysic">' + sym("battery.100percent", 10) + '</span>', t["battery"], "", "")}
<div class="foot">{t["sysfoot"]}</div>
</div>
<div class="bottom"><span class="st">{t["state"]}</span><span class="ct">{t["count"]}</span><span class="btn">{t["edit"]}</span><span class="btn">{t["off"]}</span></div>
<div class="note">{html.escape(t["note"])}</div>
</div>'''
    return BASE % (set_css, body)
for lang, t in T.items():
    open(os.path.join(work, f'settings-menubar-{lang}.html'), 'w').write(settings(t))
