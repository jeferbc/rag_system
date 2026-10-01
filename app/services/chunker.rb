# Splits text into chunks of at most +max_chars+ characters, built from whole
# paragraphs where possible. Deliberately simple: sizes and boundaries will be
# tuned against retrieval evals later.
class Chunker
  MAX_CHARS = 800
  PARAGRAPH_BREAK = /\n\s*\n/
  SENTENCE_BREAK = /(?<=[.!?])\s+/

  def self.split(text, max_chars: MAX_CHARS)
    new(max_chars).split(text)
  end

  def initialize(max_chars)
    @max_chars = max_chars
  end

  def split(text)
    paragraphs = text.to_s.gsub(/\r\n?/, "\n").split(PARAGRAPH_BREAK).map(&:strip).reject(&:empty?)
    pieces = paragraphs.flat_map { |paragraph| fit(paragraph) }

    pack(pieces, "\n\n")
  end

  private

  attr_reader :max_chars

  # A paragraph that fits is kept whole. A longer one is broken at sentence
  # boundaries, then at word boundaries, then mid-word as a last resort.
  def fit(paragraph)
    return [ paragraph ] if paragraph.length <= max_chars

    sentences = paragraph.split(SENTENCE_BREAK).flat_map do |sentence|
      next [ sentence ] if sentence.length <= max_chars

      words = sentence.split(/\s+/).flat_map { |word| word.scan(/.{1,#{max_chars}}/m) }
      pack(words, " ")
    end

    pack(sentences, " ")
  end

  # Greedily joins consecutive pieces while the result stays within max_chars.
  def pack(pieces, joiner)
    pieces.each_with_object([]) do |piece, chunks|
      if chunks.any? && chunks.last.length + joiner.length + piece.length <= max_chars
        chunks[-1] = "#{chunks.last}#{joiner}#{piece}"
      else
        chunks << piece
      end
    end
  end
end
