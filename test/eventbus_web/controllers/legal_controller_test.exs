defmodule EventbusWeb.LegalControllerTest do
  use EventbusWeb.ConnCase, async: true

  test "the privacy policy and terms render logged out, linked from the footer", %{conn: conn} do
    for {path, id} <- [{~p"/privacy", "privacy"}, {~p"/terms", "terms"}] do
      document = conn |> get(path) |> html_response(200) |> LazyHTML.from_document()

      assert LazyHTML.query(document, "article##{id} #last-updated") |> Enum.count() == 1
      assert LazyHTML.query(document, ~s(#footer-terms[href="/terms"])) |> Enum.count() == 1
      assert LazyHTML.query(document, ~s(#footer-privacy[href="/privacy"])) |> Enum.count() == 1
    end
  end
end
