#!/usr/bin/env python3
"""사용자에게 보이는 문자열과 번역 카탈로그를 맞춘다.

코드에서는 문자열을 L("…") 로 감싼다 (Packages/MenuBarKit/Sources/MenuBarUI/Strings.swift).
원문은 한국어이고 번역은 Localizable.xcstrings 에 있다.

    scripts/strings.py list     코드에서 찾은 키를 출력
    scripts/strings.py sync     카탈로그에 없는 키를 추가하고, 코드에서 사라진 키를 제거
    scripts/strings.py check    모든 키에 번역(영어, 중국어 간체)이 있는지 검사 (없으면 종료 코드 1)

삽입 값(\\(...))은 키에서 %lld(정수) 또는 %@(그 밖)로 바뀐다.
정수로 보는 경우: 식이 `.count` 로 끝나거나 `$0` 인 경우. 그 밖의 정수를 넣게 되면 이 규칙을 고친다.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = [ROOT / "App", ROOT / "Packages/MenuBarKit/Sources/MenuBarUI"]
CATALOG = ROOT / "Packages/MenuBarKit/Sources/MenuBarUI/Resources/Localizable.xcstrings"
# 번역해 두는 언어 (원문 한국어 제외). 언어를 추가하면 App/Info.plist 의 CFBundleLocalizations 와 AppLanguage 도 맞춘다.
TRANSLATIONS = {"en": "영어", "zh-Hans": "중국어"}
ESCAPES = {'"': '"', "\\": "\\", "n": "\n", "t": "\t"}


def placeholder(expression: str) -> str:
    expression = expression.strip()
    return "%lld" if expression.endswith(".count") or expression == "$0" else "%@"


def parse_literal(text: str, start: int):
    """text[start] 는 여는 따옴표 다음 글자. (키, 닫는 따옴표 다음 위치) 를 돌려준다."""
    out = []
    i = start
    while i < len(text):
        ch = text[i]
        if ch == '"':
            return "".join(out), i + 1
        if ch == "\\":
            nxt = text[i + 1]
            if nxt == "(":
                depth, j = 1, i + 2
                while depth:
                    depth += {"(": 1, ")": -1}.get(text[j], 0)
                    j += 1
                out.append(placeholder(text[i + 2 : j - 1]))
                i = j
                continue
            out.append(ESCAPES.get(nxt, nxt))
            i += 2
            continue
        out.append(ch.replace("%", "%%") if ch == "%" else ch)
        i += 1
    raise ValueError("끝나지 않은 문자열")


def keys_in_code():
    found = {}
    for base in SOURCES:
        for path in sorted(base.rglob("*.swift")):
            text = path.read_text(encoding="utf-8")
            for match in re.finditer(r'(?<![A-Za-z0-9_])L\("', text):
                key, _ = parse_literal(text, match.end())
                found.setdefault(key, str(path.relative_to(ROOT)))
    return found


def load_catalog():
    if CATALOG.exists():
        return json.loads(CATALOG.read_text(encoding="utf-8"))
    return {"sourceLanguage": "ko", "strings": {}, "version": "1.0"}


def translation(entry, language):
    return entry.get("localizations", {}).get(language, {}).get("stringUnit", {}).get("value")


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "check"
    code = keys_in_code()
    catalog = load_catalog()
    strings = catalog["strings"]

    if command == "list":
        for key, where in sorted(code.items()):
            print(f"{where}\t{key}")
        return 0

    if command == "sync":
        added = [k for k in code if k not in strings]
        removed = [k for k in strings if k not in code]
        for key in added:
            strings[key] = {}
        for key in removed:
            del strings[key]
        catalog["strings"] = dict(sorted(strings.items()))
        CATALOG.parent.mkdir(parents=True, exist_ok=True)
        CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"추가 {len(added)}개, 제거 {len(removed)}개, 전체 {len(strings)}개")
        return 0

    missing_in_catalog = [k for k in code if k not in strings]
    stale = [k for k in strings if k not in code]
    groups = [("카탈로그에 없음", missing_in_catalog), ("코드에서 사라짐", stale)]
    for language, name in TRANSLATIONS.items():
        untranslated = [k for k in code if k in strings and not translation(strings[k], language)]
        mismatched = []
        for key in code:
            value = translation(strings.get(key, {}), language)
            # 삽입 값은 종류와 순서가 원문과 같아야 한다 (번역에서 순서를 바꾸려면 %1$@ 형식을 쓴다).
            if value and re.findall(r"%(?:\d+\$)?(lld|@)", key) != re.findall(r"%(?:\d+\$)?(lld|@)", value):
                mismatched.append(key)
        groups += [(f"{name} 번역 없음", untranslated), (f"{name} 번역의 삽입 값이 원문과 다름", mismatched)]
    for title, items in groups:
        for item in items:
            print(f"[{title}] {item}")
    problems = sum(len(items) for _, items in groups)
    print(f"키 {len(code)}개 검사, 문제 {problems}개")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
