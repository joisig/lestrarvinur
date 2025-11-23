defmodule LestrarvinurPhoenix.Media do
  @moduledoc """
  Handles audio file storage and retrieval for words and encouragement messages.
  """

  @words_dir "priv/static/media/words"
  @encouragements_dir "priv/static/media/encouragements"

  @doc """
  Save an audio file for a specific word.
  Expected filename format: word_<word>.webm (or .mp3, .wav, etc.)
  Returns {:ok, path} or {:error, reason}
  """
  def save_word_audio(word, binary_data, extension \\ "webm") do
    filename = sanitize_filename("word_#{word}.#{extension}")
    path = Path.join(@words_dir, filename)

    case File.write(path, binary_data) do
      :ok -> {:ok, "/media/words/#{filename}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Save an audio file for an encouragement message.
  Expected filename format: encouragement_<index>.webm
  Index should be 0-29.
  """
  def save_encouragement_audio(index, binary_data, extension \\ "webm")
      when index >= 0 and index < 30 do
    filename = "encouragement_#{index}.#{extension}"
    path = Path.join(@encouragements_dir, filename)

    case File.write(path, binary_data) do
      :ok -> {:ok, "/media/encouragements/#{filename}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Check if audio exists for a specific word.
  Checks for common audio extensions: webm, mp3, wav, m4a
  """
  def word_audio_exists?(word) do
    extensions = ["webm", "mp3", "wav", "m4a", "ogg"]

    Enum.any?(extensions, fn ext ->
      filename = sanitize_filename("word_#{word}.#{ext}")
      path = Path.join(@words_dir, filename)
      File.exists?(path)
    end)
  end

  @doc """
  Check if audio exists for an encouragement message.
  """
  def encouragement_audio_exists?(index) when index >= 0 and index < 30 do
    extensions = ["webm", "mp3", "wav", "m4a", "ogg"]

    Enum.any?(extensions, fn ext ->
      filename = "encouragement_#{index}.#{ext}"
      path = Path.join(@encouragements_dir, filename)
      File.exists?(path)
    end)
  end

  @doc """
  Get the public URL path for a word's audio file.
  Returns nil if no audio exists for the word.
  """
  def get_word_audio_url(word) do
    extensions = ["webm", "mp3", "wav", "m4a", "ogg"]

    Enum.find_value(extensions, fn ext ->
      filename = sanitize_filename("word_#{word}.#{ext}")
      path = Path.join(@words_dir, filename)

      if File.exists?(path) do
        "/media/words/#{filename}"
      end
    end)
  end

  @doc """
  Get the public URL path for an encouragement's audio file.
  Returns nil if no audio exists.
  """
  def get_encouragement_audio_url(index) when index >= 0 and index < 30 do
    extensions = ["webm", "mp3", "wav", "m4a", "ogg"]

    Enum.find_value(extensions, fn ext ->
      filename = "encouragement_#{index}.#{ext}"
      path = Path.join(@encouragements_dir, filename)

      if File.exists?(path) do
        "/media/encouragements/#{filename}"
      end
    end)
  end

  @doc """
  Delete audio for a word.
  """
  def delete_word_audio(word) do
    extensions = ["webm", "mp3", "wav", "m4a", "ogg"]

    Enum.each(extensions, fn ext ->
      filename = sanitize_filename("word_#{word}.#{ext}")
      path = Path.join(@words_dir, filename)
      File.rm(path)
    end)

    :ok
  end

  @doc """
  Delete audio for an encouragement.
  """
  def delete_encouragement_audio(index) when index >= 0 and index < 30 do
    extensions = ["webm", "mp3", "wav", "m4a", "ogg"]

    Enum.each(extensions, fn ext ->
      filename = "encouragement_#{index}.#{ext}"
      path = Path.join(@encouragements_dir, filename)
      File.rm(path)
    end)

    :ok
  end

  # Not intended for use outside this module
  defp sanitize_filename(filename) do
    # Replace spaces and special characters with underscores
    filename
    |> String.replace(~r/[^\w\-\.]/, "_")
    |> String.downcase()
  end
end
