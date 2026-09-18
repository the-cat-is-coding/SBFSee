DROP FUNCTION IF EXISTS get_next_question();

CREATE OR REPLACE FUNCTION get_next_question()
RETURNS TABLE (
    question_id INT,
    question_text TEXT,
    theory_page VARCHAR,
    image_paths TEXT[],
    consecutive_correct INT,
    is_mastered BOOLEAN
) AS $$
DECLARE
    pick_unmastered BOOLEAN;
    unmastered_count INT;
    mastered_count INT;
BEGIN
    -- Check how many unmastered vs mastered questions exist
    SELECT COUNT(*) INTO unmastered_count 
    FROM boating_questions q 
    LEFT JOIN question_progress p ON q.id = p.question_id 
    WHERE COALESCE(p.is_mastered, FALSE) = FALSE;

    SELECT COUNT(*) INTO mastered_count 
    FROM boating_questions q 
    LEFT JOIN question_progress p ON q.id = p.question_id 
    WHERE COALESCE(p.is_mastered, FALSE) = TRUE;

    -- Handle edge cases where one category is completely empty
    IF unmastered_count = 0 THEN
        pick_unmastered := FALSE; -- Only mastered questions left
    ELSIF mastered_count = 0 THEN
        pick_unmastered := TRUE;  -- No mastered questions yet, stick to unmastered
    ELSE
        -- 80% probability (0.8) for unmastered, 20% for mastered review
        pick_unmastered := (RANDOM() < 0.8);
    END IF;

    -- Return a random question from the chosen category
    IF pick_unmastered THEN
        RETURN QUERY
        SELECT 
            q.id,
            q.question_text,
            q.theory_page,
            q.image_paths,
            COALESCE(p.consecutive_correct, 0) AS consecutive_correct,
            COALESCE(p.is_mastered, FALSE) AS is_mastered
        FROM boating_questions q
        LEFT JOIN question_progress p ON q.id = p.question_id
        WHERE COALESCE(p.is_mastered, FALSE) = FALSE
        ORDER BY RANDOM()
        LIMIT 1;
    ELSE
        RETURN QUERY
        SELECT 
            q.id,
            q.question_text,
            q.theory_page,
            q.image_paths,
            COALESCE(p.consecutive_correct, 0) AS consecutive_correct,
            COALESCE(p.is_mastered, FALSE) AS is_mastered
        FROM boating_questions q
        LEFT JOIN question_progress p ON q.id = p.question_id
        WHERE COALESCE(p.is_mastered, FALSE) = TRUE
        ORDER BY RANDOM()
        LIMIT 1;
    END IF;
END;
$$ LANGUAGE plpgsql;