-- Core questions table
CREATE TABLE boating_questions (
    id INT PRIMARY KEY,
    question_text TEXT NOT NULL,
    theory_page VARCHAR(50),
    image_path VARCHAR(255) -- For signs, lights, and symbols
);

-- Multiple choice options table (Option 'a' from ELWIS/book is stored as is_correct = true)
CREATE TABLE boating_options (
    id SERIAL PRIMARY KEY,
    question_id INT REFERENCES boating_questions(id) ON DELETE CASCADE,
    option_text TEXT NOT NULL,
    is_correct BOOLEAN NOT NULL
);

-- Progress tracking per question
CREATE TABLE question_progress (
    question_id INT PRIMARY KEY REFERENCES boating_questions(id) ON DELETE CASCADE,
    consecutive_correct INT DEFAULT 0,
    total_correct INT DEFAULT 0,
    total_incorrect INT DEFAULT 0,
    is_mastered BOOLEAN DEFAULT FALSE,
    last_reviewed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Add a text array column to the main table
ALTER TABLE boating_questions 
ADD COLUMN IF NOT EXISTS image_paths TEXT[] DEFAULT '{}';

-- 1. Enable RLS on all your tables
ALTER TABLE boating_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE boating_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE question_progress ENABLE ROW LEVEL SECURITY;

-- 2. Allow public read access to questions and options
CREATE POLICY "Allow public read questions" 
ON boating_questions FOR SELECT 
USING (true);

CREATE POLICY "Allow public read options" 
ON boating_options FOR SELECT 
USING (true);

-- 3. Allow full access (read, insert, update) for your progress tracker
CREATE POLICY "Allow public full access progress" 
ON question_progress FOR ALL 
USING (true) 
WITH CHECK (true);