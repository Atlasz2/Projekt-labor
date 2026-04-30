import re

file_path = r"admin\src\pages\Stations.jsx"

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Sections array - Media tab eltávolítása
content = content.replace(
    "const sections = ['🏷️ Alap adatok', '📍 Helyszín', '📖 Tartalom', '🔓 Feloldható info', '🖼️ Média'];",
    "const sections = ['🏷️ Alap adatok', '📍 Helyszín', '📖 Tartalom', '🔓 Feloldható info'];"
)

# 2. activeSection === 4 teljes blokk eltávolítása
pattern = r'\n\s+\{activeSection === 4 && \(.*?\n\s+\)\}'
content = re.sub(pattern, '', content, flags=re.DOTALL)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("OK: Media tab removed, section 4 deleted")
