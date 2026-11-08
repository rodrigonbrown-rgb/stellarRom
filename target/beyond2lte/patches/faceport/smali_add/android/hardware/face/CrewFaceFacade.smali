.class public final Landroid/hardware/face/CrewFaceFacade;
.super Ljava/lang/Object;
.source "CrewFaceFacade.java"

# crew: routes android.hardware.face.FaceManager to Samsung's legacy face stack
# (SemBioFaceManager -> BioFaceService "samsung.face" -> faced) when
# ro.crew.legacy_face=true. Never active in system_server (process name null).

.field private static sMgr:Lcom/samsung/android/bio/face/SemBioFaceManager;


.method public constructor <init>()V
    .locals 0
    invoke-direct {p0}, Ljava/lang/Object;-><init>()V
    return-void
.end method

.method public static on(Landroid/hardware/face/FaceManager;)Z
    .locals 3

    const/4 v0, 0x0

    if-eqz p0, :cond_false

    :try_start_0
    const-string v1, "ro.crew.legacy_face"

    invoke-static {v1, v0}, Landroid/os/SystemProperties;->getBoolean(Ljava/lang/String;Z)Z

    move-result v1

    if-eqz v1, :cond_false

    invoke-static {}, Landroid/app/Application;->getProcessName()Ljava/lang/String;

    move-result-object v1

    if-eqz v1, :cond_false

    const-string v2, "system_server"

    invoke-virtual {v2, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v1

    if-nez v1, :cond_false

    invoke-static {p0}, Landroid/hardware/face/FaceManager;->-$$Nest$fgetmContext(Landroid/hardware/face/FaceManager;)Landroid/content/Context;

    move-result-object v1

    if-eqz v1, :cond_false
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :cond_false

    const/4 v0, 0x1

    :cond_false
    return v0
.end method

.method private static mgr(Landroid/hardware/face/FaceManager;)Lcom/samsung/android/bio/face/SemBioFaceManager;
    .locals 2

    sget-object v0, Landroid/hardware/face/CrewFaceFacade;->sMgr:Lcom/samsung/android/bio/face/SemBioFaceManager;

    if-nez v0, :cond_done

    invoke-static {p0}, Landroid/hardware/face/FaceManager;->-$$Nest$fgetmContext(Landroid/hardware/face/FaceManager;)Landroid/content/Context;

    move-result-object v0

    invoke-virtual {v0}, Landroid/content/Context;->getApplicationContext()Landroid/content/Context;

    move-result-object v1

    if-eqz v1, :cond_use

    move-object v0, v1

    :cond_use
    invoke-static {v0}, Lcom/samsung/android/bio/face/SemBioFaceManager;->getInstance(Landroid/content/Context;)Lcom/samsung/android/bio/face/SemBioFaceManager;

    move-result-object v0

    sput-object v0, Landroid/hardware/face/CrewFaceFacade;->sMgr:Lcom/samsung/android/bio/face/SemBioFaceManager;

    :cond_done
    return-object v0
.end method

.method public static hasEnrolled(Landroid/hardware/face/FaceManager;)Z
    .locals 1

    invoke-static {}, Landroid/os/UserHandle;->myUserId()I

    move-result v0

    invoke-static {p0, v0}, Landroid/hardware/face/CrewFaceFacade;->hasEnrolled(Landroid/hardware/face/FaceManager;I)Z

    move-result v0

    return v0
.end method

.method public static hasEnrolled(Landroid/hardware/face/FaceManager;I)Z
    .locals 1

    :try_start_0
    invoke-static {p0}, Landroid/hardware/face/CrewFaceFacade;->mgr(Landroid/hardware/face/FaceManager;)Lcom/samsung/android/bio/face/SemBioFaceManager;

    move-result-object v0

    invoke-virtual {v0, p1}, Lcom/samsung/android/bio/face/SemBioFaceManager;->hasEnrolledFaces(I)Z

    move-result v0
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    return v0

    :catch_0
    const/4 v0, 0x0

    return v0
.end method

.method public static getEnrolled(Landroid/hardware/face/FaceManager;)Ljava/util/List;
    .locals 1

    invoke-static {}, Landroid/os/UserHandle;->myUserId()I

    move-result v0

    invoke-static {p0, v0}, Landroid/hardware/face/CrewFaceFacade;->getEnrolled(Landroid/hardware/face/FaceManager;I)Ljava/util/List;

    move-result-object v0

    return-object v0
.end method

.method public static getEnrolled(Landroid/hardware/face/FaceManager;I)Ljava/util/List;
    .locals 8

    new-instance v0, Ljava/util/ArrayList;

    invoke-direct {v0}, Ljava/util/ArrayList;-><init>()V

    :try_start_0
    invoke-static {p0}, Landroid/hardware/face/CrewFaceFacade;->mgr(Landroid/hardware/face/FaceManager;)Lcom/samsung/android/bio/face/SemBioFaceManager;

    move-result-object v1

    invoke-virtual {v1, p1}, Lcom/samsung/android/bio/face/SemBioFaceManager;->getEnrolledFaces(I)Ljava/util/List;

    move-result-object v1

    if-eqz v1, :cond_done

    invoke-interface {v1}, Ljava/util/List;->iterator()Ljava/util/Iterator;

    move-result-object v1

    :goto_loop
    invoke-interface {v1}, Ljava/util/Iterator;->hasNext()Z

    move-result v2

    if-eqz v2, :cond_done

    invoke-interface {v1}, Ljava/util/Iterator;->next()Ljava/lang/Object;

    move-result-object v2

    check-cast v2, Lcom/samsung/android/bio/face/SemBioFace;

    invoke-virtual {v2}, Lcom/samsung/android/bio/face/SemBioFace;->getName()Ljava/lang/CharSequence;

    move-result-object v4

    if-nez v4, :cond_named

    const-string v4, "Face"

    :cond_named
    invoke-virtual {v2}, Lcom/samsung/android/bio/face/SemBioFace;->getFaceId()I

    move-result v5

    invoke-virtual {v2}, Lcom/samsung/android/bio/face/SemBioFace;->getDeviceId()J

    move-result-wide v6

    new-instance v3, Landroid/hardware/face/Face;

    invoke-direct {v3, v4, v5, v6, v7}, Landroid/hardware/face/Face;-><init>(Ljava/lang/CharSequence;IJ)V

    invoke-interface {v0, v3}, Ljava/util/List;->add(Ljava/lang/Object;)Z

    goto :goto_loop
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :cond_done

    :cond_done
    return-object v0
.end method

.method public static remove(Landroid/hardware/face/FaceManager;Landroid/hardware/face/Face;ILandroid/hardware/face/FaceManager$RemovalCallback;)V
    .locals 7

    :try_start_0
    invoke-static {p0}, Landroid/hardware/face/CrewFaceFacade;->mgr(Landroid/hardware/face/FaceManager;)Lcom/samsung/android/bio/face/SemBioFaceManager;

    move-result-object v0

    invoke-virtual {p1}, Landroid/hardware/biometrics/BiometricAuthenticator$Identifier;->getName()Ljava/lang/CharSequence;

    move-result-object v2

    move v3, p2

    invoke-virtual {p1}, Landroid/hardware/biometrics/BiometricAuthenticator$Identifier;->getBiometricId()I

    move-result v4

    invoke-virtual {p1}, Landroid/hardware/biometrics/BiometricAuthenticator$Identifier;->getDeviceId()J

    move-result-wide v5

    new-instance v1, Lcom/samsung/android/bio/face/SemBioFace;

    invoke-direct/range {v1 .. v6}, Lcom/samsung/android/bio/face/SemBioFace;-><init>(Ljava/lang/CharSequence;IIJ)V

    goto :goto_built
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    :goto_built
    :try_start_1
    new-instance v2, Landroid/hardware/face/CrewFaceFacade$Removal;

    invoke-direct {v2, p0, p1, p2, p3}, Landroid/hardware/face/CrewFaceFacade$Removal;-><init>(Landroid/hardware/face/FaceManager;Landroid/hardware/face/Face;ILandroid/hardware/face/FaceManager$RemovalCallback;)V

    invoke-virtual {v0, v1, p2, v2}, Lcom/samsung/android/bio/face/SemBioFaceManager;->remove(Lcom/samsung/android/bio/face/SemBioFace;ILcom/samsung/android/bio/face/SemBioFaceManager$RemovalCallback;)V
    :try_end_1
    .catch Ljava/lang/Throwable; {:try_start_1 .. :try_end_1} :catch_0

    return-void

    :catch_0
    if-eqz p3, :cond_ret

    const/4 v0, 0x6

    const-string v1, "Face removal failed"

    invoke-virtual {p3, p1, v0, v1}, Landroid/hardware/face/FaceManager$RemovalCallback;->onRemovalError(Landroid/hardware/face/Face;ILjava/lang/CharSequence;)V

    :cond_ret
    return-void
.end method

.method public static removeAll(Landroid/hardware/face/FaceManager;ILandroid/hardware/face/FaceManager$RemovalCallback;)V
    .locals 3

    invoke-static {p0, p1}, Landroid/hardware/face/CrewFaceFacade;->getEnrolled(Landroid/hardware/face/FaceManager;I)Ljava/util/List;

    move-result-object v0

    invoke-interface {v0}, Ljava/util/List;->isEmpty()Z

    move-result v1

    if-eqz v1, :cond_has

    if-eqz p2, :cond_ret

    const/4 v1, 0x0

    const/4 v2, 0x0

    invoke-virtual {p2, v1, v2}, Landroid/hardware/face/FaceManager$RemovalCallback;->onRemovalSucceeded(Landroid/hardware/face/Face;I)V

    :cond_ret
    return-void

    :cond_has
    const/4 v1, 0x0

    invoke-interface {v0, v1}, Ljava/util/List;->get(I)Ljava/lang/Object;

    move-result-object v0

    check-cast v0, Landroid/hardware/face/Face;

    invoke-static {p0, v0, p1, p2}, Landroid/hardware/face/CrewFaceFacade;->remove(Landroid/hardware/face/FaceManager;Landroid/hardware/face/Face;ILandroid/hardware/face/FaceManager$RemovalCallback;)V

    return-void
.end method

.method public static genChallenge(Landroid/hardware/face/FaceManager;IILandroid/hardware/face/FaceManager$GenerateChallengeCallback;)V
    .locals 0

    invoke-static {p0, p2, p3}, Landroid/hardware/face/CrewFaceFacade;->genChallenge(Landroid/hardware/face/FaceManager;ILandroid/hardware/face/FaceManager$GenerateChallengeCallback;)V

    return-void
.end method

.method public static genChallenge(Landroid/hardware/face/FaceManager;ILandroid/hardware/face/FaceManager$GenerateChallengeCallback;)V
    .locals 2

    # crew: legacy preEnroll() is a stub that returns 0; the real challenge comes from
    # preEnroll(ChallengeCallback) -> BioFaceService -> TA, delivered async to onPreEnroll(J)
    :try_start_0
    invoke-static {p0}, Landroid/hardware/face/CrewFaceFacade;->mgr(Landroid/hardware/face/FaceManager;)Lcom/samsung/android/bio/face/SemBioFaceManager;

    move-result-object v0

    new-instance v1, Landroid/hardware/face/CrewFaceFacade$PreEnroll;

    invoke-direct {v1, p2, p1}, Landroid/hardware/face/CrewFaceFacade$PreEnroll;-><init>(Landroid/hardware/face/FaceManager$GenerateChallengeCallback;I)V

    invoke-virtual {v0, v1}, Lcom/samsung/android/bio/face/SemBioFaceManager;->preEnroll(Lcom/samsung/android/bio/face/SemBioFaceManager$ChallengeCallback;)J
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    :catch_0
    return-void
.end method

.method public static revoke(Landroid/hardware/face/FaceManager;IIJ)V
    .locals 1

    :try_start_0
    invoke-static {p0}, Landroid/hardware/face/CrewFaceFacade;->mgr(Landroid/hardware/face/FaceManager;)Lcom/samsung/android/bio/face/SemBioFaceManager;

    move-result-object v0

    invoke-virtual {v0}, Lcom/samsung/android/bio/face/SemBioFaceManager;->postEnroll()I
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    :catch_0
    return-void
.end method

.method public static enroll5(Landroid/hardware/face/FaceManager;I[BLandroid/os/CancellationSignal;Landroid/hardware/face/FaceManager$EnrollmentCallback;[I)V
    .locals 0

    invoke-static {p0, p1, p2, p3, p4}, Landroid/hardware/face/CrewFaceFacade;->enrollCore(Landroid/hardware/face/FaceManager;I[BLandroid/os/CancellationSignal;Landroid/hardware/face/FaceManager$EnrollmentCallback;)V

    return-void
.end method

.method public static enroll8(Landroid/hardware/face/FaceManager;I[BLandroid/os/CancellationSignal;Landroid/hardware/face/FaceManager$EnrollmentCallback;[ILandroid/view/Surface;ZLandroid/hardware/face/FaceEnrollOptions;)V
    .locals 0

    invoke-static {p0, p1, p2, p3, p4}, Landroid/hardware/face/CrewFaceFacade;->enrollCore(Landroid/hardware/face/FaceManager;I[BLandroid/os/CancellationSignal;Landroid/hardware/face/FaceManager$EnrollmentCallback;)V

    return-void
.end method

.method public static enrollCore(Landroid/hardware/face/FaceManager;I[BLandroid/os/CancellationSignal;Landroid/hardware/face/FaceManager$EnrollmentCallback;)V
    .locals 8

    :try_start_0
    invoke-static {p0}, Landroid/hardware/face/CrewFaceFacade;->mgr(Landroid/hardware/face/FaceManager;)Lcom/samsung/android/bio/face/SemBioFaceManager;

    move-result-object v0

    new-instance v5, Landroid/hardware/face/CrewFaceFacade$Enroll;

    invoke-direct {v5, p4}, Landroid/hardware/face/CrewFaceFacade$Enroll;-><init>(Landroid/hardware/face/FaceManager$EnrollmentCallback;)V

    move-object v1, p2

    move-object v2, p3

    const/4 v3, 0x0

    move v4, p1

    const/4 v6, 0x0

    invoke-static {p0}, Landroid/hardware/face/CrewFaceFacade;->previewView(Landroid/hardware/face/FaceManager;)Landroid/view/View;

    move-result-object v7

    invoke-virtual/range {v0 .. v7}, Lcom/samsung/android/bio/face/SemBioFaceManager;->enroll([BLandroid/os/CancellationSignal;IILcom/samsung/android/bio/face/SemBioFaceManager$EnrollmentCallback;Landroid/os/Bundle;Landroid/view/View;)V
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    return-void

    :catch_0
    if-eqz p4, :cond_ret

    const/4 v0, 0x1

    const-string v1, "Face unlock unavailable"

    invoke-virtual {p4, v0, v1}, Landroid/hardware/face/FaceManager$EnrollmentCallback;->onEnrollmentError(ILjava/lang/CharSequence;)V

    :cond_ret
    return-void
.end method

.method public static pause(Landroid/hardware/face/FaceManager;)V
    .locals 1

    :try_start_0
    invoke-static {p0}, Landroid/hardware/face/CrewFaceFacade;->mgr(Landroid/hardware/face/FaceManager;)Lcom/samsung/android/bio/face/SemBioFaceManager;

    move-result-object v0

    invoke-virtual {v0}, Lcom/samsung/android/bio/face/SemBioFaceManager;->requestEnrollPause()V
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    :catch_0
    return-void
.end method

.method public static resume(Landroid/hardware/face/FaceManager;)V
    .locals 1

    :try_start_0
    invoke-static {p0}, Landroid/hardware/face/CrewFaceFacade;->mgr(Landroid/hardware/face/FaceManager;)Lcom/samsung/android/bio/face/SemBioFaceManager;

    move-result-object v0

    invoke-virtual {v0}, Lcom/samsung/android/bio/face/SemBioFaceManager;->requestEnrollResume()V
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    :catch_0
    return-void
.end method

.method public static sessionOpen(Landroid/hardware/face/FaceManager;I)V
    .locals 1

    :try_start_0
    invoke-static {p0}, Landroid/hardware/face/CrewFaceFacade;->mgr(Landroid/hardware/face/FaceManager;)Lcom/samsung/android/bio/face/SemBioFaceManager;

    move-result-object v0

    invoke-virtual {v0}, Lcom/samsung/android/bio/face/SemBioFaceManager;->requestSessionOpen()V
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    :catch_0
    return-void
.end method

.method public static sessionClose(Landroid/hardware/face/FaceManager;I)V
    .locals 1

    :try_start_0
    invoke-static {p0}, Landroid/hardware/face/CrewFaceFacade;->mgr(Landroid/hardware/face/FaceManager;)Lcom/samsung/android/bio/face/SemBioFaceManager;

    move-result-object v0

    invoke-virtual {v0}, Lcom/samsung/android/bio/face/SemBioFaceManager;->requestSessionClose()V
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    :catch_0
    return-void
.end method

.method public static resetTimeout(Landroid/hardware/face/FaceManager;)Z
    .locals 1

    :try_start_0
    invoke-static {p0}, Landroid/hardware/face/CrewFaceFacade;->mgr(Landroid/hardware/face/FaceManager;)Lcom/samsung/android/bio/face/SemBioFaceManager;

    move-result-object v0

    invoke-virtual {v0}, Lcom/samsung/android/bio/face/SemBioFaceManager;->resetAuthenticationTimeout()Z

    move-result v0
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    return v0

    :catch_0
    const/4 v0, 0x0

    return v0
.end method

.method public static isEnrollSession(Landroid/hardware/face/FaceManager;)Z
    .locals 1

    :try_start_0
    invoke-static {p0}, Landroid/hardware/face/CrewFaceFacade;->mgr(Landroid/hardware/face/FaceManager;)Lcom/samsung/android/bio/face/SemBioFaceManager;

    move-result-object v0

    invoke-virtual {v0}, Lcom/samsung/android/bio/face/SemBioFaceManager;->isEnrollSession()Z

    move-result v0
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    return v0

    :catch_0
    const/4 v0, 0x0

    return v0
.end method

.method public static remainingLockout(Landroid/hardware/face/FaceManager;I)I
    .locals 1

    :try_start_0
    invoke-static {p0}, Landroid/hardware/face/CrewFaceFacade;->mgr(Landroid/hardware/face/FaceManager;)Lcom/samsung/android/bio/face/SemBioFaceManager;

    move-result-object v0

    invoke-virtual {v0, p1}, Lcom/samsung/android/bio/face/SemBioFaceManager;->getRemainingLockoutTime(I)I

    move-result v0
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    return v0

    :catch_0
    const/4 v0, 0x0

    return v0
.end method

# crew: legacy BioFaceService needs the caller's preview View (window token + rect) for enrollment.
# One UI 9 BiometricSetting passes only a Surface, so take the largest TextureView/SurfaceView of the
# calling Activity (FaceManager.mContext is the Activity), else its decor view.
.method private static previewView(Landroid/hardware/face/FaceManager;)Landroid/view/View;
    .locals 8

    :try_start_0
    invoke-static {p0}, Landroid/hardware/face/FaceManager;->-$$Nest$fgetmContext(Landroid/hardware/face/FaceManager;)Landroid/content/Context;

    move-result-object v0

    :goto_unwrap
    if-eqz v0, :cond_null

    instance-of v1, v0, Landroid/app/Activity;

    if-nez v1, :cond_act

    instance-of v1, v0, Landroid/content/ContextWrapper;

    if-eqz v1, :cond_null

    check-cast v0, Landroid/content/ContextWrapper;

    invoke-virtual {v0}, Landroid/content/ContextWrapper;->getBaseContext()Landroid/content/Context;

    move-result-object v0

    goto :goto_unwrap

    :cond_act
    check-cast v0, Landroid/app/Activity;

    invoke-virtual {v0}, Landroid/app/Activity;->getWindow()Landroid/view/Window;

    move-result-object v0

    if-eqz v0, :cond_null

    invoke-virtual {v0}, Landroid/view/Window;->getDecorView()Landroid/view/View;

    move-result-object v0

    if-eqz v0, :cond_null

    new-instance v1, Ljava/util/ArrayList;

    invoke-direct {v1}, Ljava/util/ArrayList;-><init>()V

    invoke-virtual {v1, v0}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z

    const/4 v2, 0x0

    const/4 v3, 0x0

    :goto_loop
    invoke-virtual {v1}, Ljava/util/ArrayList;->isEmpty()Z

    move-result v4

    if-nez v4, :cond_done

    invoke-virtual {v1}, Ljava/util/ArrayList;->size()I

    move-result v4

    add-int/lit8 v4, v4, -0x1

    invoke-virtual {v1, v4}, Ljava/util/ArrayList;->remove(I)Ljava/lang/Object;

    move-result-object v4

    check-cast v4, Landroid/view/View;

    instance-of v5, v4, Landroid/view/TextureView;

    if-nez v5, :cond_cand

    instance-of v5, v4, Landroid/view/SurfaceView;

    if-eqz v5, :cond_kids

    :cond_cand
    invoke-virtual {v4}, Landroid/view/View;->getWidth()I

    move-result v5

    invoke-virtual {v4}, Landroid/view/View;->getHeight()I

    move-result v6

    mul-int/2addr v5, v6

    if-le v5, v3, :cond_kids

    move-object v2, v4

    move v3, v5

    :cond_kids
    instance-of v5, v4, Landroid/view/ViewGroup;

    if-eqz v5, :goto_loop

    check-cast v4, Landroid/view/ViewGroup;

    invoke-virtual {v4}, Landroid/view/ViewGroup;->getChildCount()I

    move-result v5

    const/4 v6, 0x0

    :goto_kid
    if-ge v6, v5, :goto_loop

    invoke-virtual {v4, v6}, Landroid/view/ViewGroup;->getChildAt(I)Landroid/view/View;

    move-result-object v7

    if-eqz v7, :cond_next

    invoke-virtual {v1, v7}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z

    :cond_next
    add-int/lit8 v6, v6, 0x1

    goto :goto_kid

    :cond_done
    if-eqz v2, :cond_decor

    return-object v2

    :cond_decor
    return-object v0
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :cond_null

    :cond_null
    const/4 v0, 0x0

    return-object v0
.end method
