defmodule LestrarvinurPhoenix.Repo.Migrations.ShiftMathLevelsForConfidenceLevels do
  use Ecto.Migration

  @moduledoc """
  Four new confidence-building levels were inserted below the old math level 1,
  so old levels 1-12 became levels 5-16. Shift stored per-level counts by +4
  and reset saved sequences (they embed the old level ids).
  """

  def up do
    execute """
    UPDATE users
    SET math_level_counts = COALESCE(
          (SELECT json_group_object(CAST(CAST(key AS INTEGER) + 4 AS TEXT), value)
           FROM json_each(users.math_level_counts)),
          '{}'
        ),
        math_shuffled_sequence = '[]',
        math_current_index = 0
    """
  end

  def down do
    # Shift back, dropping counts for the four new levels (they have no old id).
    execute """
    UPDATE users
    SET math_level_counts = COALESCE(
          (SELECT json_group_object(CAST(CAST(key AS INTEGER) - 4 AS TEXT), value)
           FROM json_each(users.math_level_counts)
           WHERE CAST(key AS INTEGER) > 4),
          '{}'
        ),
        math_shuffled_sequence = '[]',
        math_current_index = 0
    """
  end
end
