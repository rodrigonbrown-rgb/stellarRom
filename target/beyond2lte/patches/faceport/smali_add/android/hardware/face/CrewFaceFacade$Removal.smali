.class final Landroid/hardware/face/CrewFaceFacade$Removal;
.super Lcom/samsung/android/bio/face/SemBioFaceManager$RemovalCallback;
.source "CrewFaceFacade.java"

.field final cb:Landroid/hardware/face/FaceManager$RemovalCallback;

.field final face:Landroid/hardware/face/Face;

.field final fm:Landroid/hardware/face/FaceManager;

.field final user:I


.method constructor <init>(Landroid/hardware/face/FaceManager;Landroid/hardware/face/Face;ILandroid/hardware/face/FaceManager$RemovalCallback;)V
    .locals 0

    invoke-direct {p0}, Lcom/samsung/android/bio/face/SemBioFaceManager$RemovalCallback;-><init>()V

    iput-object p1, p0, Landroid/hardware/face/CrewFaceFacade$Removal;->fm:Landroid/hardware/face/FaceManager;

    iput-object p2, p0, Landroid/hardware/face/CrewFaceFacade$Removal;->face:Landroid/hardware/face/Face;

    iput p3, p0, Landroid/hardware/face/CrewFaceFacade$Removal;->user:I

    iput-object p4, p0, Landroid/hardware/face/CrewFaceFacade$Removal;->cb:Landroid/hardware/face/FaceManager$RemovalCallback;

    return-void
.end method

.method public onRemovalError(Lcom/samsung/android/bio/face/SemBioFace;ILjava/lang/CharSequence;)V
    .locals 2

    iget-object v0, p0, Landroid/hardware/face/CrewFaceFacade$Removal;->cb:Landroid/hardware/face/FaceManager$RemovalCallback;

    if-eqz v0, :cond_0

    iget-object v1, p0, Landroid/hardware/face/CrewFaceFacade$Removal;->face:Landroid/hardware/face/Face;

    invoke-virtual {v0, v1, p2, p3}, Landroid/hardware/face/FaceManager$RemovalCallback;->onRemovalError(Landroid/hardware/face/Face;ILjava/lang/CharSequence;)V

    :cond_0
    return-void
.end method

.method public onRemovalSucceeded(Lcom/samsung/android/bio/face/SemBioFace;)V
    .locals 3

    iget-object v0, p0, Landroid/hardware/face/CrewFaceFacade$Removal;->cb:Landroid/hardware/face/FaceManager$RemovalCallback;

    if-eqz v0, :cond_0

    iget-object v1, p0, Landroid/hardware/face/CrewFaceFacade$Removal;->fm:Landroid/hardware/face/FaceManager;

    iget v2, p0, Landroid/hardware/face/CrewFaceFacade$Removal;->user:I

    invoke-static {v1, v2}, Landroid/hardware/face/CrewFaceFacade;->getEnrolled(Landroid/hardware/face/FaceManager;I)Ljava/util/List;

    move-result-object v1

    invoke-interface {v1}, Ljava/util/List;->size()I

    move-result v1

    iget-object v2, p0, Landroid/hardware/face/CrewFaceFacade$Removal;->face:Landroid/hardware/face/Face;

    invoke-virtual {v0, v2, v1}, Landroid/hardware/face/FaceManager$RemovalCallback;->onRemovalSucceeded(Landroid/hardware/face/Face;I)V

    :cond_0
    return-void
.end method
