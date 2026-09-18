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

    try:
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
                
                # Extract all consecutive images bound to this question
                image_urls = find_all_question_images(elem)

                # Gather options precisely
                options = []
                curr = elem.parent
                
                for _ in range(12):
                    if not curr:
                        break
                    curr = curr.find_next_sibling()
                    
                    # Stop gathering if we hit the next question header
                    if curr and curr.get_text() and re.search(r"^\d+\.\s+", curr.get_text().strip()):
                        break

                    if curr:
                        for img in curr.find_all("img"):
                            img.decompose()
                        
                        text_blocks = [p.get_text().strip() for p in curr.find_all(['p', 'div', 'li']) if p.get_text().strip()]
                        if not text_blocks:
                            txt = curr.get_text().strip()
                            if txt:
                                text_blocks = [txt]

                        for block in text_blocks:
                            sub_lines = block.split('\n')
                            for line in sub_lines:
                                clean_line = line.strip()
                                if clean_line and not re.match(r"^\d+\.\s+", clean_line) and "Anmerkung" not in clean_line:
                                    clean_line = re.sub(r"^[a-d]\)\s*", "", clean_line, flags=re.IGNORECASE).strip()
                                    if clean_line and clean_line not in options and len(clean_line) > 1:
                                        options.append(clean_line)
                    
                    if len(options) >= 4:
                        break

                if len(options) >= 4:
                    save_question(cur, q_id, q_text, options[:4], image_urls)
                    total_inserted += 1

            conn.commit()
            print(f"Finished processing {category}.")

    except Exception as e:
        conn.rollback()
        print(f"\n[ABORTED] Error encountered during seeding: {e}")
        raise
    finally:
        cur.close()
        conn.close()
        print(f"Database connection closed. Total questions processed: {total_inserted}")

def find_all_question_images(elem):
    """
    Finds all consecutive images associated with the question in its immediate parent 
    or direct next sibling block before any options or text begin.
    """
    image_urls = []
    parent = elem.parent
    
    imgs = parent.find_all("img")
    if not imgs:
        next_sib = parent.find_next_sibling()
        if next_sib:
            imgs = next_sib.find_all("img")

    for img in imgs:
        src = img.get("src")
        if src:
            full_url = f"https://www.elwis.de{src}" if src.startswith("/") else src
            if full_url not in image_urls:
                image_urls.append(full_url)
                
    return image_urls

def save_question(cur, q_id, q_text, options, image_urls):
    if image_urls is None:
        image_urls = []

    # Upsert question text and image_paths array
    cur.execute("""
        INSERT INTO boating_questions (id, question_text, image_paths)
        VALUES (%s, %s, %s)
        ON CONFLICT (id) DO UPDATE 
        SET question_text = EXCLUDED.question_text,
            image_paths = EXCLUDED.image_paths;
    """, (q_id, q_text, image_urls))

    # Clear old options to prevent duplicates
    cur.execute("DELETE FROM boating_options WHERE question_id = %s;", (q_id,))

    # Insert options
    for idx, opt_text in enumerate(options):
        is_correct = (idx == 0)
        cur.execute("""
            INSERT INTO boating_options (question_id, option_text, is_correct)
            VALUES (%s, %s, %s);
        """, (q_id, opt_text, is_correct))
    
    print(f"Saved Question {q_id} with {len(options)} options and {len(image_urls)} image(s).")

if __name__ == "__main__":
    seed_database()