.class final Landroid/hardware/face/CrewFaceFacade$Enroll;
.super Lcom/samsung/android/bio/face/SemBioFaceManager$EnrollmentCallback;
.source "CrewFaceFacade.java"

.field final cb:Landroid/hardware/face/FaceManager$EnrollmentCallback;


.method constructor <init>(Landroid/hardware/face/FaceManager$EnrollmentCallback;)V
    .locals 0

    invoke-direct {p0}, Lcom/samsung/android/bio/face/SemBioFaceManager$EnrollmentCallback;-><init>()V

    iput-object p1, p0, Landroid/hardware/face/CrewFaceFacade$Enroll;->cb:Landroid/hardware/face/FaceManager$EnrollmentCallback;

    return-void
.end method

.method public onEnrollmentError(ILjava/lang/CharSequence;)V
    .locals 1

    iget-object v0, p0, Landroid/hardware/face/CrewFaceFacade$Enroll;->cb:Landroid/hardware/face/FaceManager$EnrollmentCallback;

    if-eqz v0, :cond_0

    invoke-virtual {v0, p1, p2}, Landroid/hardware/face/FaceManager$EnrollmentCallback;->onEnrollmentError(ILjava/lang/CharSequence;)V

    :cond_0
    return-void
.end method

.method public onEnrollmentHelp(ILjava/lang/CharSequence;)V
    .locals 1

    iget-object v0, p0, Landroid/hardware/face/CrewFaceFacade$Enroll;->cb:Landroid/hardware/face/FaceManager$EnrollmentCallback;

    if-eqz v0, :cond_0

    invoke-virtual {v0, p1, p2}, Landroid/hardware/face/FaceManager$EnrollmentCallback;->onEnrollmentHelp(ILjava/lang/CharSequence;)V

    :cond_0
    return-void
.end method

.method public onEnrollmentProgress(I)V
    .locals 1

    # crew: legacy reports percent done, One UI 9 BiometricSetting expects remaining (it shows 100 - x)
    rsub-int/lit8 p1, p1, 0x64

    iget-object v0, p0, Landroid/hardware/face/CrewFaceFacade$Enroll;->cb:Landroid/hardware/face/FaceManager$EnrollmentCallback;

    if-eqz v0, :cond_0

    invoke-virtual {v0, p1}, Landroid/hardware/face/FaceManager$EnrollmentCallback;->onEnrollmentProgress(I)V

    :cond_0
    return-void
.end method

.method public onImageProcessed([BIIIILandroid/os/Bundle;)V
    .locals 7

    iget-object v0, p0, Landroid/hardware/face/CrewFaceFacade$Enroll;->cb:Landroid/hardware/face/FaceManager$EnrollmentCallback;

    if-eqz v0, :cond_0

    move-object v1, p1

    move v2, p2

    move v3, p3

    move v4, p4

    move v5, p5

    move-object v6, p6

    invoke-virtual/range {v0 .. v6}, Landroid/hardware/face/FaceManager$EnrollmentCallback;->onImageProcessed([BIIIILandroid/os/Bundle;)V

    :cond_0
    return-void
.end method
