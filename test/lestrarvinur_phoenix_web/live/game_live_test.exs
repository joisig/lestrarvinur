defmodule LestrarvinurPhoenixWeb.GameLiveTest do
  use ExUnit.Case, async: true

  alias LestrarvinurPhoenixWeb.GameLive

  describe "personalize_phrase/2" do
    test "substitutes the login name into the placeholder phrase" do
      assert GameLive.personalize_phrase("Ég heiti Tómas", "solla") == "Ég heiti Solla"
      assert GameLive.personalize_phrase("Ég heiti Tómas", "Árni") == "Ég heiti Árni"
    end

    test "leaves every other word and phrase untouched" do
      assert GameLive.personalize_phrase("Hvað heitir þú?", "solla") == "Hvað heitir þú?"
      assert GameLive.personalize_phrase("hestur", "solla") == "hestur"
    end
  end
end
