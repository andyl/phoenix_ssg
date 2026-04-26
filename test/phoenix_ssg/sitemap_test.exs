defmodule PhoenixSsg.SitemapTest do
  use ExUnit.Case, async: true

  alias PhoenixSsg.Sitemap

  test "renders a well-formed urlset with sorted entries" do
    xml = Sitemap.generate(["/about", "/"], "https://example.com")

    assert xml =~ ~s|<?xml version="1.0" encoding="UTF-8"?>|
    assert xml =~ ~s|xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"|
    assert xml =~ "<loc>https://example.com/</loc>"
    assert xml =~ "<loc>https://example.com/about</loc>"

    pos_root = :binary.match(xml, "https://example.com/<") |> elem(0)
    pos_about = :binary.match(xml, "https://example.com/about") |> elem(0)
    assert pos_root < pos_about
  end

  test "trims trailing slash from base_url" do
    xml = Sitemap.generate(["/foo"], "https://example.com/")
    assert xml =~ "<loc>https://example.com/foo</loc>"
    refute xml =~ "https://example.com//foo"
  end

  test "escapes XML-special characters in loc" do
    xml = Sitemap.generate(["/a&b", "/c<d>"], "https://x.com")
    assert xml =~ "/a&amp;b"
    assert xml =~ "/c&lt;d&gt;"
    refute xml =~ "/a&b<"
  end
end
