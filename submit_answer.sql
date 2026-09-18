import re
import requests
from bs4 import BeautifulSoup
import psycopg2
from db_config import DB_HOST, DB_NAME, DB_USER, DB_PASSWORD, DB_PORT

URLS = [
    ("Basisfragen", "https://www.elwis.de/DE/Sportschifffahrt/Sportbootfuehrerscheine/Fragenkatalog-See/Basisfragen/Basisfragen-node"),
    ("Spezifische Fragen See", "https://www.elwis.de/DE/Sportschifffahrt/Sportbootfuehrerscheine/Fragenkatalog-See/Spezifische-Fragen-See/Spezifische-Fragen-See-node")
]

def seed_database():
    print("Connecting to Supabase PostgreSQL database...")
    conn = psycopg2.connect(
        host=DB_HOST, database=DB_NAME, user=DB_USER, password=DB_PASSWORD, port=DB_PORT
    )
    cur = conn.cursor()

    total_inserted = 0

    for category, url in URLS:
        print(f"Fetching {category} from: {url}")
        response = requests.get(url)
        response.encoding = 'utf-8'

        if response.status_code != 200:
            print(f"Failed to fetch {url}, status: {response.status_code}")
            continue

        soup = BeautifulSoup(response.text, 'html.parser')
        
        question_pattern = re.compile(r"^(\d+)\.\s+(.*)")
        elements = soup.find_all(string=question_pattern)
        print(f"Found {len(elements)} potential question markers in {category}.")

        for elem in elements:
            match = question_pattern.match(elem.strip())
            if not match:
                continue
            
            q_id = int(match.group(1))
            q_text = match.group(2)
            image_url = find_question_image_only(elem)

            # Find option elements. ELWIS usually places options in subsequent siblings.
            options = []
            curr = elem.parent
            
            for _ in range(12):
                if not curr:
                    break
                curr = curr.find_next_sibling()
                if curr:
                    for img in curr.find_all("img"):
                        img.decompose()
                    
                    # Extract text blocks
                    text_blocks = [p.get_text().strip() for p in curr.find_all(['p', 'div', 'li']) if p.get_text().strip()]
                    if not text_blocks:
                        txt = curr.get_text().strip()
                        if txt:
                            text_blocks = [txt]

                    for block in text_blocks:
                        # Split potential multi-line blocks
                        sub_lines = block.split('\n')
                        for line in sub_lines:
                            clean_line = line.strip()
                            # Filter out question numbers, headers, and notes
                            if clean_line and not re.match(r"^\d+\.\s+", clean_line) and "Anmerkung" not in clean_line:
                                # Strip leading a), b), c), d) if present
                                clean_line = re.sub(r"^[a-d]\)\s*", "", clean_line, flags=re.IGNORECASE).strip()
                                if clean_line and clean_line not in options and len(clean_line) > 1:
                                    options.append(clean_line)
                
                if len(options) >= 4:
                    break

            if len(options) >= 4:
                save_question(cur, q_id, q_text, options[:4], image_url)
                total_inserted += 1

        conn.commit()
        print(f"Finished processing {category}.")

    cur.close()
    conn.close()
    print(f"Database seeding completed successfully! Total questions processed: {total_inserted}")

def find_question_image_only(elem):
    parent = elem.parent
    img = parent.find("img") or parent.find_next("img")
    if img:
        src = img.get("src")
        if src:
            if src.startswith("/"):
                return f"https://www.elwis.de{src}"
            return src
    return None

def save_question(cur, q_id, q_text, options, image_url):
    cur.execute("""
        INSERT INTO boating_questions (id, question_text, image_path)
        VALUES (%s, %s, %s)
        ON CONFLICT (id) DO UPDATE 
        SET question_text = EXCLUDED.question_text,
            image_path = EXCLUDED.image_path;
    """, (q_id, q_text, image_url))

    cur.execute("DELETE FROM boating_options WHERE question_id = %s;", (q_id,))

    for idx, opt_text in enumerate(options):
        is_correct = (idx == 0)
        cur.execute("""
            INSERT INTO boating_options (question_id, option_text, is_correct)
            VALUES (%s, %s, %s);
        """, (q_id, opt_text, is_correct))
    
    print(f"Saved Question {q_id} with 4 clean options.")

if __name__ == "__main__":
    seed_database()