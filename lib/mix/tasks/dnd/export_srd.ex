defmodule Mix.Tasks.Dnd.ExportSrd do
  use Mix.Task

  @shortdoc "dnd_reference_ko 데이터를 SRD/PHB별로 분리하여 priv/data/srd/, priv/data/phb/에 저장"

  @moduledoc """
  dnd_reference_ko 레포의 JSON 데이터를 source 필드 기준으로 분리하여
  priv/data/srd/ (SRD 5.2) 와 priv/data/phb/ (PHB 2024) 에 저장한다.

  ## 사용법

      mix dnd.export_srd --source /path/to/dnd_reference_ko/src/data

  ## 옵션

    * `--source` - 소스 데이터 디렉토리 경로 (필수)
  """

  # 배열 기반 파일 (source 필드로 그룹핑)
  @array_files [
    "classes.json",
    "races.json",
    "backgrounds.json",
    "feats.json",
    "spells.json",
    "subclasses.json",
    "weapons.json",
    "armor.json",
    "adventuringGear.json",
    "tools.json",
    "monsters.json"
  ]

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:jason)

    {opts, _, _} = OptionParser.parse(args, strict: [source: :string])

    source_dir =
      opts[:source] ||
        Mix.raise("--source 옵션이 필요합니다. 예: mix dnd.export_srd --source ../dnd_reference_ko/dnd_korean/dnd-reference/src/data")

    unless File.dir?(source_dir) do
      Mix.raise("소스 디렉토리를 찾을 수 없습니다: #{source_dir}")
    end

    srd_dir = Path.join(["priv", "data", "srd"])
    phb_dir = Path.join(["priv", "data", "phb"])
    File.mkdir_p!(srd_dir)
    File.mkdir_p!(phb_dir)

    Mix.shell().info("소스: #{source_dir}")
    Mix.shell().info("출력: #{srd_dir}, #{phb_dir}")
    Mix.shell().info("")

    # 배열 기반 파일 처리
    for file <- @array_files do
      process_array_file(source_dir, srd_dir, phb_dir, file)
    end

    # classFeatures.json: 전체 SRD, 객체 구조 (class_id → [features])
    process_all_srd_object_file(source_dir, srd_dir, "classFeatures.json")

    # subclassFeatures.json: 혼재, 서브클래스 ID 기준으로 분리
    process_subclass_features(source_dir, srd_dir, phb_dir)

    Mix.shell().info("")
    Mix.shell().info("완료! priv/data/srd/ 및 priv/data/phb/ 파일을 git에 추가하세요.")
  end

  defp process_array_file(source_dir, srd_dir, phb_dir, file) do
    path = Path.join(source_dir, file)

    if File.exists?(path) do
      {:ok, content} = File.read(path)
      {:ok, data} = Jason.decode(content)

      case data do
        data when is_list(data) ->
          {srd, phb} = Enum.split_with(data, &(&1["source"] == "SRD 5.2"))

          write_json(Path.join(srd_dir, file), srd)

          if phb != [] do
            write_json(Path.join(phb_dir, file), phb)
          end

          Mix.shell().info("  #{file}: SRD #{length(srd)}건, PHB #{length(phb)}건")

        data when is_map(data) ->
          # 객체 구조 파일 — 전체 SRD로 간주하고 srd/에 복사
          write_json(Path.join(srd_dir, file), data)
          Mix.shell().info("  #{file}: 객체 구조, 전체 srd/ 복사")
      end
    else
      Mix.shell().info("  [건너뜀] #{file} — 파일 없음")
    end
  end

  defp process_all_srd_object_file(source_dir, srd_dir, file) do
    path = Path.join(source_dir, file)

    if File.exists?(path) do
      {:ok, content} = File.read(path)
      {:ok, data} = Jason.decode(content)

      write_json(Path.join(srd_dir, file), data)
      Mix.shell().info("  #{file}: 전체 SRD #{map_size(data)}개 클래스")
    else
      Mix.shell().info("  [건너뜀] #{file} — 파일 없음")
    end
  end

  defp process_subclass_features(source_dir, srd_dir, phb_dir) do
    subclasses_path = Path.join(source_dir, "subclasses.json")
    features_path = Path.join(source_dir, "subclassFeatures.json")

    if File.exists?(subclasses_path) && File.exists?(features_path) do
      {:ok, sc_content} = File.read(subclasses_path)
      {:ok, subclasses} = Jason.decode(sc_content)
      srd_ids = subclasses |> Enum.filter(&(&1["source"] == "SRD 5.2")) |> Enum.map(& &1["id"]) |> MapSet.new()

      {:ok, sf_content} = File.read(features_path)
      {:ok, data} = Jason.decode(sf_content)

      {srd_map, phb_map} =
        Enum.reduce(data, {%{}, %{}}, fn {key, features}, {srd, phb} ->
          if MapSet.member?(srd_ids, key) do
            {Map.put(srd, key, features), phb}
          else
            {srd, Map.put(phb, key, features)}
          end
        end)

      write_json(Path.join(srd_dir, "subclassFeatures.json"), srd_map)

      if map_size(phb_map) > 0 do
        write_json(Path.join(phb_dir, "subclassFeatures.json"), phb_map)
      end

      Mix.shell().info(
        "  subclassFeatures.json: SRD #{map_size(srd_map)}개 서브클래스, PHB #{map_size(phb_map)}개 서브클래스"
      )
    else
      Mix.shell().info("  [건너뜀] subclassFeatures.json — 필요 파일 없음")
    end
  end

  defp write_json(path, data) do
    File.write!(path, Jason.encode!(data, pretty: true))
  end
end
