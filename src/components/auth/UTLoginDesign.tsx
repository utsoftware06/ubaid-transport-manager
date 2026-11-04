"use client";

import { useState, type FormEventHandler } from "react";
import Image from "next/image";
import Link from "next/link";
import {
  ChartNoAxesCombined,
  Eye,
  EyeOff,
  FileText,
  Loader2,
  LockKeyhole,
  LogIn,
  Mail,
  MapPin,
  Truck,
  Users,
  Wallet,
  Warehouse,
} from "lucide-react";

import VoiceTypingField from "@/components/shared/VoiceTypingField";
import { useLanguage } from "@/contexts/LanguageContext";

import styles from "./UTLoginDesign.module.css";

type Props = {
  email: string;
  password: string;
  onEmailChange: (value: string) => void;
  onPasswordChange: (value: string) => void;
  onSubmit: FormEventHandler<HTMLFormElement>;
  isLoading: boolean;
  error: string | null;
  successNotice?: string | null;
};

export default function UTLoginDesign({
  email,
  password,
  onEmailChange,
  onPasswordChange,
  onSubmit,
  isLoading,
  error,
  successNotice = null,
}: Props) {
  const { language, setLanguage, t, dir } = useLanguage();
  const [showPassword, setShowPassword] = useState(false);

  const features = [
    { icon: Truck, label: "auth.login.features.loadingBilty" },
    { icon: Wallet, label: "auth.login.features.accountsLedgers" },
    { icon: FileText, label: "auth.login.features.vouchersParchi" },
    { icon: ChartNoAxesCombined, label: "auth.login.features.reportsProfit" },
    { icon: Users, label: "auth.login.features.multiAdda" },
  ] as const;

  return (
    <main className={styles.shell} dir="ltr">
      <section
        className={styles.hero}
        dir={dir}
        aria-labelledby="login-hero-title"
      >
        <Image
          src="/ut-login-truck.png"
          alt=""
          fill
          priority
          sizes="(max-width: 850px) 100vw, 52vw"
          className={styles.truckBackground}
        />
        <div className={styles.heroShade} aria-hidden="true" />
        <div className={styles.curvedDivider} aria-hidden="true" />

        <div className={styles.heroContent}>
          <div className={styles.brandLockup} dir="ltr">
            <span className={styles.brandTruck} aria-hidden="true">
              <Truck />
            </span>
            <span className={styles.brandWords}>
              <span className={styles.brandName}>UT Software</span>
              <span className={styles.brandSubtitle}>
                {t("auth.login.brandSubtitle")}
              </span>
            </span>
          </div>

          <h1 id="login-hero-title" className={styles.heroTitle}>
            <span>{t("auth.login.heroTitle")}</span>{" "}
            <strong>{t("auth.login.heroSystem")}</strong>
          </h1>
          <p className={styles.heroDescription}>
            {t("auth.login.heroDescription")}
          </p>

          <div className={styles.featureGrid}>
            {features.map(({ icon: Icon, label }) => (
              <div className={styles.featureCard} key={label}>
                <Icon className={styles.featureIcon} aria-hidden="true" />
                <span>{t(label)}</span>
              </div>
            ))}
          </div>

          <p className={styles.secureTag}>
            <Users aria-hidden="true" />
            <span>{t("auth.login.secureMultiAdda")}</span>
          </p>
        </div>
      </section>

      <section className={styles.signInPanel} aria-label={t("auth.login.title")}>
        <div className={styles.languageRow}>
          <div
            className={styles.languageSwitch}
            role="group"
            aria-label={t("auth.login.languageLabel")}
            dir="ltr"
          >
            <button
              type="button"
              onClick={() => setLanguage("en")}
              aria-pressed={language === "en"}
              className={language === "en" ? styles.languageActive : undefined}
            >
              {t("auth.login.english")}
            </button>
            <button
              type="button"
              onClick={() => setLanguage("ur")}
              aria-pressed={language === "ur"}
              className={language === "ur" ? styles.languageActive : undefined}
            >
              {t("auth.login.urdu")}
            </button>
          </div>
        </div>

        <div className={styles.cardStage}>
          <div className={styles.loginCard} dir={dir}>
            <header className={styles.cardHeader}>
              <div className={styles.cardBrand} dir="ltr">
                <Truck aria-hidden="true" />
                <span>UT Software</span>
              </div>
              <p className={styles.cardBrandSubtitle}>
                {t("auth.login.brandSubtitle")}
              </p>
              <h2>{t("auth.login.title")}</h2>
              <p className={styles.cardDescription}>
                {t("auth.login.cardDescription")}
              </p>
            </header>

            {successNotice ? (
              <p role="status" className={styles.successNotice}>
                {successNotice}
              </p>
            ) : null}

            <form onSubmit={onSubmit} className={styles.loginForm}>
              <div className={styles.fieldGroup}>
                <label htmlFor="login-email" className={styles.fieldLabel}>
                  {t("auth.email")}
                </label>
                <div className={styles.fieldShell}>
                  <Mail className={styles.fieldIcon} aria-hidden="true" />
                  <div className={styles.voiceField}>
                    <VoiceTypingField
                      fieldLabel={t("auth.email")}
                      mode="email"
                      contextKey="login-email"
                    >
                      <input
                        id="login-email"
                        name="email"
                        type="email"
                        autoComplete="email"
                        autoCapitalize="none"
                        spellCheck={false}
                        dir="ltr"
                        value={email}
                        onChange={(event) => onEmailChange(event.target.value)}
                        placeholder={t("auth.login.emailPlaceholder")}
                        required
                        disabled={isLoading}
                        className={styles.fieldInput}
                      />
                    </VoiceTypingField>
                  </div>
                </div>
              </div>

              <div className={styles.fieldGroup}>
                <label htmlFor="login-password" className={styles.fieldLabel}>
                  {t("auth.password")}
                </label>
                <div className={styles.fieldShell}>
                  <LockKeyhole className={styles.fieldIcon} aria-hidden="true" />
                  <input
                    id="login-password"
                    name="password"
                    type={showPassword ? "text" : "password"}
                    autoComplete="current-password"
                    dir="ltr"
                    value={password}
                    onChange={(event) => onPasswordChange(event.target.value)}
                    placeholder={t("auth.login.passwordPlaceholder")}
                    required
                    disabled={isLoading}
                    className={styles.fieldInput}
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword((visible) => !visible)}
                    disabled={isLoading}
                    aria-label={
                      showPassword
                        ? t("auth.login.hidePassword")
                        : t("auth.login.showPassword")
                    }
                    aria-pressed={showPassword}
                    className={styles.passwordToggle}
                  >
                    {showPassword ? (
                      <EyeOff aria-hidden="true" />
                    ) : (
                      <Eye aria-hidden="true" />
                    )}
                  </button>
                </div>
              </div>

              <div className={styles.forgotRow}>
                <Link href="/forgot-password" className={styles.textLink}>
                  {t("auth.login.forgotPassword")}
                </Link>
              </div>

              {error && (
                <p role="alert" aria-live="assertive" className={styles.error}>
                  {error}
                </p>
              )}

              <button
                type="submit"
                disabled={isLoading}
                aria-busy={isLoading}
                className={styles.submitButton}
              >
                {isLoading ? (
                  <Loader2 className={styles.spinner} aria-hidden="true" />
                ) : (
                  <LogIn aria-hidden="true" />
                )}
                <span>
                  {isLoading
                    ? t("auth.login.submitting")
                    : t("auth.login.submit")}
                </span>
              </button>

              {isLoading && (
                <span role="status" className={styles.srOnly}>
                  {t("auth.login.submitting")}
                </span>
              )}
            </form>

            <p className={styles.accountAccess}>
              <Link href="/register" className={styles.textLink}>
                {t("auth.login.createAccount")}
              </Link>
            </p>

            <p className={styles.cardFooter} dir="ltr">
              {t("auth.login.footer")}
            </p>

            <div className={styles.cardFleet} aria-hidden="true">
              <span className={styles.fleetSkyline} />
              <MapPin className={styles.fleetPinOne} />
              <Truck className={styles.fleetTruckOne} />
              <Truck className={styles.fleetTruckTwo} />
              <Warehouse className={styles.fleetWarehouse} />
              <MapPin className={styles.fleetPinTwo} />
            </div>
          </div>
        </div>
      </section>
    </main>
  );
}
