defmodule TrpgMaster.Campaign.Persistence.FilesTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.Campaign.Persistence.Files

  test "campaign_dir/1 sanitizes unsafe path characters" do
    path = Files.campaign_dir("boss:/raid?*alpha")

    assert path =~ Path.join("campaigns", "boss__raid__alpha")
    refute path =~ "?"
    refute path =~ "*"
    refute path =~ ":"
  end

  test "summary_path/1 appends campaign summary filename" do
    assert Files.summary_path("alpha") =~
             Path.join(["campaigns", "alpha", "campaign-summary.json"])
  end
end
