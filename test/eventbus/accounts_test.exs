defmodule Eventbus.AccountsTest do
  use Eventbus.DataCase, async: true

  import Eventbus.AccountsFixtures
  import Swoosh.TestAssertions

  alias Eventbus.{Accounts, Applications}
  alias Eventbus.Accounts.{Scope, User, UserToken}

  describe "create_superadmin/1" do
    test "creates the first user as superadmin with a hashed password" do
      refute Accounts.any_users?()

      assert {:ok, %User{} = user} =
               Accounts.create_superadmin(%{
                 email: "  admin@example.com ",
                 password: valid_password()
               })

      assert user.email == "admin@example.com"
      assert user.role == "superadmin"
      assert user.confirmed_at
      assert user.accepted_terms_at
      assert is_binary(user.hashed_password)
      assert is_nil(user.password)
      assert Accounts.any_users?()
    end

    test "refuses once a user exists" do
      user_fixture()

      assert {:error, :already_set_up} =
               Accounts.create_superadmin(valid_user_attributes())
    end

    test "validates email and password" do
      assert {:error, changeset} =
               Accounts.create_superadmin(%{
                 email: "not an email",
                 password: "short",
                 password_confirmation: "different"
               })

      errors = errors_on(changeset)
      assert "must have the @ sign and no spaces" in errors.email
      assert "should be at least 12 character(s)" in errors.password
      assert "does not match password" in errors.password_confirmation
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "returns the user for valid credentials, case-insensitive email" do
      user = user_fixture(email: "jorge@example.com")

      assert %User{id: id} =
               Accounts.get_user_by_email_and_password(" JORGE@example.com", valid_password())

      assert id == user.id
    end

    test "returns nil for a wrong password or unknown user" do
      user = user_fixture()
      refute Accounts.get_user_by_email_and_password(user.email, "wrong password!")
      refute Accounts.get_user_by_email_and_password("nobody@example.com", valid_password())
    end
  end

  test "emails are unique regardless of case" do
    user_fixture(email: "taken@example.com")

    assert {:error, changeset} =
             %User{}
             |> User.registration_changeset(valid_user_attributes(email: "TAKEN@example.com"))
             |> User.role_changeset("member")
             |> Repo.insert()

    assert "has already been taken" in errors_on(changeset).email
  end

  describe "session tokens" do
    setup do
      user = user_fixture()
      %{user: user, token: Accounts.generate_user_session_token(user)}
    end

    test "resolve to the user", %{user: user, token: token} do
      assert Accounts.get_user_by_session_token(token).id == user.id
    end

    test "stop working once deleted", %{token: token} do
      assert :ok = Accounts.delete_user_session_token(token)
      refute Accounts.get_user_by_session_token(token)
    end

    test "expire", %{token: token} do
      expired = DateTime.add(DateTime.utc_now(), -UserToken.session_validity_in_days() - 1, :day)
      Repo.update_all(UserToken, set: [inserted_at: expired])
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "register_user/1" do
    defp signup_attrs(overrides \\ %{}) do
      Enum.into(overrides, %{
        email: unique_user_email(),
        password: valid_password(),
        password_confirmation: valid_password(),
        terms: "true"
      })
    end

    test "creates an unconfirmed member with a sandbox app" do
      assert {:ok, user} = Accounts.register_user(signup_attrs())

      assert user.role == "member"
      assert user.confirmed_at == nil
      assert user.accepted_terms_at

      assert [%{slug: "sandbox-" <> _}] =
               Applications.list_apps_with_topic_counts(Scope.for_user(user))
    end

    test "requires accepting the terms and creates nothing otherwise" do
      assert {:error, changeset} = Accounts.register_user(signup_attrs(terms: "false"))
      assert "must be accepted to sign up" in errors_on(changeset).terms
      refute Accounts.any_users?()
    end

    test "rejects a taken email" do
      user_fixture(email: "taken@example.com")

      assert {:error, changeset} =
               Accounts.register_user(signup_attrs(email: "Taken@example.com"))

      assert "has already been taken" in errors_on(changeset).email
    end
  end

  describe "deliver_user_confirmation_instructions/2" do
    setup do
      %{user: user_fixture(confirmed: false)}
    end

    test "emails a link with a token that only exists hashed", %{user: user} do
      assert {:ok, email} =
               Accounts.deliver_user_confirmation_instructions(user, capture_token_url())

      assert email == user.email
      assert_received {:token, token}

      assert_email_sent(fn sent ->
        assert sent.to == [{"", user.email}]
        assert sent.subject == "Confirm your eventbus email"
        assert sent.text_body =~ "https://eventbus.test/#{token}"
      end)

      assert %UserToken{token: stored, sent_to: sent_to} =
               Repo.get_by(UserToken, context: "confirm")

      assert sent_to == user.email
      refute stored == token
    end

    test "waits a minute between links", %{user: user} do
      assert {:ok, _} = Accounts.deliver_user_confirmation_instructions(user, & &1)
      assert {:error, :cooldown} = Accounts.deliver_user_confirmation_instructions(user, & &1)
    end

    test "skips confirmed users" do
      assert {:error, :already_confirmed} =
               Accounts.deliver_user_confirmation_instructions(user_fixture(), & &1)
    end
  end

  describe "confirm_user/1" do
    setup do
      user = user_fixture(confirmed: false)
      {:ok, _} = Accounts.deliver_user_confirmation_instructions(user, capture_token_url())
      assert_received {:token, token}
      %{user: user, token: token}
    end

    test "confirms once", %{user: user, token: token} do
      assert {:ok, confirmed} = Accounts.confirm_user(token)
      assert confirmed.id == user.id
      assert confirmed.confirmed_at
      refute Repo.get_by(UserToken, user_id: user.id, context: "confirm")

      assert :error = Accounts.confirm_user(token)
    end

    test "rejects expired tokens", %{token: token} do
      Repo.update_all(UserToken, set: [inserted_at: DateTime.add(DateTime.utc_now(), -8, :day)])
      assert :error = Accounts.confirm_user(token)
    end

    test "rejects a token sent to a previous email", %{user: user, token: token} do
      Repo.update_all(from(u in User, where: u.id == ^user.id), set: [email: "new@example.com"])
      assert :error = Accounts.confirm_user(token)
    end

    test "rejects tampered and malformed tokens", %{token: token} do
      assert :error = Accounts.confirm_user(token <> "x")
      assert :error = Accounts.confirm_user("not base64!")
    end
  end
end
