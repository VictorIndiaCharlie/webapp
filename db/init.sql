CREATE TABLE IF NOT EXISTS words (
    id             SERIAL PRIMARY KEY,
    word           VARCHAR(100) UNIQUE NOT NULL,
    sorted_letters VARCHAR(100) NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_words_sorted_letters ON words (sorted_letters);

-- Insert names and automatically calculate their sorted anagram key
INSERT INTO words (word, sorted_letters)
SELECT w,
       (SELECT string_agg(c, '' ORDER BY c)
        FROM unnest(string_to_array(lower(w), '')) AS c)
FROM unnest(ARRAY[
    -- Romanian Names
    'andrei', 'andreea', 'alexandru', 'maria', 'elena', 'ioana', 
    'mihai', 'gabriel', 'ana', 'cristian', 'daniel', 'luca', 
    'stefan', 'ionut', 'alina', 'alexandra', 'bogdan', 'catalin', 
    'dragos', 'florin', 'george', 'ion', 'laurentiu', 'marius', 
    'nicolae', 'oana', 'paul', 'radu', 'sorin', 'tudor', 'vasile',
    'dumitru', 'gheorghe', 'constantin', 'adrian', 'cornel', 'vlad',
    
    -- General European & Universal Names
    'matteo', 'sophie', 'luis', 'pierre', 'giulia', 'hans', 
    'klaus', 'nikola', 'olga', 'sven', 'ivan', 'lars', 'emma', 
    'olivia', 'liam', 'noah', 'lucas', 'sofia', 'alice', 'hugo', 
    'arthur', 'leo', 'adam', 'david', 'karl', 'franz', 'giovanni', 
    'isabella', 'charlotte', 'amelia', 'mia', 'leon', 'felix', 
    'maximilian', 'anna', 'lena', 'nina', 'clara', 'laura', 
    'julia', 'sara', 'elisa', 'martina', 'francesca', 'chiara'
]) AS w
ON CONFLICT (word) DO NOTHING;