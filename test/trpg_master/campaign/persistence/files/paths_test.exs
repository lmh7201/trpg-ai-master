defmodule TrpgMaster.Campaign.Persistence.Files.PathsTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.Campaign.Persistence.Files.Paths

  describe "sanitize_filename/1" do
    test "정상 파일명은 그대로 보존한다" do
      assert Paths.sanitize_filename("campaign-abc") == "campaign-abc"
      assert Paths.sanitize_filename("한글이름") == "한글이름"
    end

    test "경로 구분자를 치환한다" do
      assert Paths.sanitize_filename("a/b") == "a_b"
      assert Paths.sanitize_filename("a\\b") == "a_b"
    end

    test "Windows 예약 문자를 치환한다" do
      assert Paths.sanitize_filename("a:b") == "a_b"
      assert Paths.sanitize_filename("a*b") == "a_b"
      assert Paths.sanitize_filename("a?b") == "a_b"
      assert Paths.sanitize_filename(~s(a"b)) == "a_b"
      assert Paths.sanitize_filename("a<b") == "a_b"
      assert Paths.sanitize_filename("a>b") == "a_b"
      assert Paths.sanitize_filename("a|b") == "a_b"
    end

    test "NUL 등 제어 문자를 치환한다" do
      assert Paths.sanitize_filename("a\0b") == "a_b"
      assert Paths.sanitize_filename("a\tb") == "a_b"
      assert Paths.sanitize_filename("a\nb") == "a_b"
    end

    test "앞뒤 공백을 제거한다" do
      assert Paths.sanitize_filename("  name  ") == "name"
    end

    test "..를 포함한 경로 순회 시도는 제거한다" do
      assert Paths.sanitize_filename("..") == "_"
      assert Paths.sanitize_filename("...") == "_"
      assert Paths.sanitize_filename("..hidden") == "hidden"
      assert Paths.sanitize_filename("name..") == "name"
    end

    test "앞뒤 점을 제거한다" do
      assert Paths.sanitize_filename(".hidden") == "hidden"
      assert Paths.sanitize_filename("name.") == "name"
    end

    test "빈 문자열/공백만 있는 경우 '_'를 돌려준다" do
      assert Paths.sanitize_filename("") == "_"
      assert Paths.sanitize_filename("   ") == "_"
      assert Paths.sanitize_filename("...") == "_"
      assert Paths.sanitize_filename("/") == "_"
    end

    test "비문자열 입력은 '_'를 돌려준다" do
      assert Paths.sanitize_filename(nil) == "_"
      assert Paths.sanitize_filename(123) == "_"
      assert Paths.sanitize_filename(%{}) == "_"
    end
  end

  describe "campaign_dir/1" do
    test "위험한 id도 campaigns_dir 밖으로 벗어나지 않는다" do
      dir = Paths.campaign_dir("..")
      assert String.ends_with?(dir, "/_")
      refute String.contains?(dir, "/../")
    end

    test "정상 id는 campaigns_dir 아래에 위치한다" do
      dir = Paths.campaign_dir("abc")
      assert String.ends_with?(dir, "/abc")
    end
  end

  describe "경로 헬퍼" do
    test "각 헬퍼는 전달된 디렉터리 아래 정해진 파일명을 만든다" do
      dir = "/tmp/campaigns/xyz"

      assert Paths.campaign_summary_path(dir) == dir <> "/campaign-summary.json"
      assert Paths.characters_dir(dir) == dir <> "/characters"
      assert Paths.npcs_dir(dir) == dir <> "/npcs"
      assert Paths.exploration_history_path(dir) == dir <> "/exploration_history.json"
      assert Paths.legacy_exploration_history_path(dir) == dir <> "/conversation_history.json"
      assert Paths.combat_history_path(dir) == dir <> "/combat_history.json"
      assert Paths.journal_path(dir) == dir <> "/journal.json"
      assert Paths.context_summary_path(dir) == dir <> "/context_summary.json"
    end
  end
end
