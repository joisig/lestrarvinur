defmodule LestrarvinurPhoenix.Repo.Migrations.ResetReadingSequencesForPhrases do
  use Ecto.Migration

  @moduledoc """
  Phrases and new words were added to the reading game and the sequence
  generator now interleaves phrases. Reset saved reading sequences so the new
  mix takes effect on next play instead of after the old sequence finishes.
  Total words read and trophies are unaffected.
  """

  def up do
    execute """
    UPDATE users
    SET shuffled_sequence = '[]',
        current_word_index = 0
    """
  end

  def down do
    # Nothing to restore — sequences regenerate on next play either way.
    :ok
  end
end
